#!/usr/bin/env bash
#
# Extract screenshot attachments from an .xcresult bundle.
#
# Usage:
#   extract_screenshots.sh <xcresult_path> <device> <output_dir> [resize_WxH]
#
# Writes bare shot names (e.g. 01_card_front.png) into <output_dir>.
# Callers pass e.g. screenshots/<run>/default/iphone as <output_dir>.
#
set -euo pipefail

XCRESULT="$1"
DEVICE="$2"
OUTPUT_DIR="$3"
RESIZE="${4:-}"

if [ ! -d "$XCRESULT" ]; then
    echo "Error: xcresult not found at $XCRESULT" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Export all attachments to a temp directory
TMPDIR_EXPORT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_EXPORT"' EXIT

xcrun xcresulttool export attachments \
    --path "$XCRESULT" \
    --output-path "$TMPDIR_EXPORT" 2>/dev/null

MANIFEST="$TMPDIR_EXPORT/manifest.json"
if [ ! -f "$MANIFEST" ]; then
    echo "Error: No manifest.json found after export" >&2
    exit 1
fi

# Parse manifest and rename files with proper names
COUNT=$(python3 -c "
import json, os, sys

manifest = json.load(open('$MANIFEST'))
output_dir = '$OUTPUT_DIR'
count = 0

for test_entry in manifest:
    for att in test_entry.get('attachments', []):
        src = os.path.join('$TMPDIR_EXPORT', att['exportedFileName'])
        # Use suggested name, strip the UUID suffix
        suggested = att.get('suggestedHumanReadableName', att['exportedFileName'])
        # Extract the meaningful part (e.g., '01_card_front' from '01_card_front_0_UUID.png')
        parts = suggested.rsplit('.', 1)
        name_parts = parts[0].split('_')
        # Find where the UUID starts (after _0_)
        clean_name = parts[0]
        for i, p in enumerate(name_parts):
            if p == '0' and i > 0 and i < len(name_parts) - 1:
                # Check if next part looks like a UUID
                if len(name_parts[i+1]) > 8 and '-' in name_parts[i+1]:
                    clean_name = '_'.join(name_parts[:i])
                    break

        dst = os.path.join(output_dir, f'{clean_name}.png')
        if os.path.exists(src):
            os.rename(src, dst)
            count += 1

print(count)
")

# Resize if requested
if [ -n "$RESIZE" ] && [ "$COUNT" -gt 0 ]; then
    W=$(echo "$RESIZE" | cut -dx -f1)
    H=$(echo "$RESIZE" | cut -dx -f2)
    for f in "$OUTPUT_DIR"/*.png; do
        [ -f "$f" ] || continue
        sips --resampleHeightWidth "$H" "$W" "$f" >/dev/null 2>&1
        echo "  Resized: $f"
    done
fi

echo "Extracted $COUNT screenshots for $DEVICE -> $OUTPUT_DIR"
