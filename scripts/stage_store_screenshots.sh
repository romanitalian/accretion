#!/usr/bin/env bash
#
# Copy captioned screenshots into fastlane/screenshots/<locale>/ for `deliver`.
#
# Usage: stage_store_screenshots.sh <texted_dir> <locale>...
#   <texted_dir> is a screenshots run's framed/texted folder with iphone/ and ipad/ inside.
# deliver tells devices apart by image size; the iphone_/ipad_ prefix only keeps the order readable.
set -euo pipefail

SRC="${1:?texted dir required}"; shift
[ -d "$SRC" ] || { echo "No captioned screenshots at '$SRC': run make screenshots-text" >&2; exit 1; }
OUT="$(cd "$(dirname "$0")/.." && pwd)/fastlane/screenshots"

for loc in "$@"; do
    mkdir -p "$OUT/$loc"
    find "$OUT/$loc" -maxdepth 1 -name '*.png' -delete
    for dev in iphone ipad; do
        for f in "$SRC/$dev"/*.png; do
            [ -f "$f" ] && cp "$f" "$OUT/$loc/${dev}_$(basename "$f")"
        done
    done
    echo "  $loc: $(find "$OUT/$loc" -name '*.png' | wc -l | tr -d ' ') screenshots"
done
echo "Screenshots from $SRC → fastlane/screenshots/"
