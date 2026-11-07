#!/usr/bin/env bash
#
# Put device frames around App Store screenshots with fastlane frameit.
#
# Usage: frame_screenshots.sh <run_dir>
#   reads  <run_dir>/default/{iphone,ipad}/*.png
#   writes <run_dir>/framed/plain/{iphone,ipad}/*.png at App Store sizes
#
# frameit only knows older device frames, so shots are resized to a frame it has
# (iPhone 6.5", iPad 12.9"), framed, then resized to the final upload size and flattened (no alpha).
set -euo pipefail

RUN_DIR="${1:?run dir required}"
IPHONE_OUT="1284x2778"   # 6.5" iPhone, accepted by App Store Connect
IPAD_OUT="2064x2752"     # 13" iPad

staging="$(mktemp -d "$RUN_DIR/.frameit_staging.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

for device in iphone ipad; do
    mkdir -p "$RUN_DIR/framed/plain/$device"
    for f in "$RUN_DIR/default/$device"/*.png; do
        [ -f "$f" ] || continue
        dst="$staging/$device-$(basename "$f")"
        cp "$f" "$dst"
        case "$device" in
            iphone) sips --resampleHeightWidth 2778 1284 "$dst" >/dev/null ;;
            ipad)   sips --resampleHeightWidth 2732 2048 "$dst" >/dev/null ;;
        esac
    done
done

echo "--- Applying device frames (fastlane frameit) ---"
# frameit exits 0 even when it fails, so the log is kept and shown if nothing gets framed.
log="$staging/frameit.log"
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 FASTLANE_SKIP_UPDATE_CHECK=1 PATH="/opt/homebrew/opt/ruby/bin:$PATH" \
    bundle exec fastlane run frameit path:"$staging" >"$log" 2>&1 || true
if ! ls "$staging"/*_framed.png >/dev/null 2>&1; then
    grep -v "warning:" "$log" | tail -20
    echo "frameit produced no framed screenshots" >&2
    exit 1
fi

fail=0
for f in "$staging"/*_framed.png; do
    [ -f "$f" ] || continue
    stem="$(basename "$f" _framed.png)"
    device="${stem%%-*}"
    shot="${stem#*-}"
    out="$RUN_DIR/framed/plain/$device/$shot.png"
    mv "$f" "$out"
    size="$IPHONE_OUT"; [ "$device" = ipad ] && size="$IPAD_OUT"
    w="${size%x*}"; h="${size#*x}"
    sips --resampleHeightWidth "$h" "$w" "$out" >/dev/null
    # App Store Connect rejects screenshots with an alpha channel: round-trip through JPEG.
    sips -s format jpeg "$out" --out "$staging/flat.jpg" >/dev/null
    sips -s format png "$staging/flat.jpg" --out "$out" >/dev/null
    got_w=$(sips -g pixelWidth "$out" | awk '/pixelWidth/{print $2}')
    got_h=$(sips -g pixelHeight "$out" | awk '/pixelHeight/{print $2}')
    if [ "$got_w" = "$w" ] && [ "$got_h" = "$h" ]; then
        echo "  ✓ framed/plain/$device/$shot.png  ${got_w}×${got_h}"
    else
        echo "  ✗ framed/plain/$device/$shot.png  ${got_w}×${got_h} (expected ${w}×${h})"
        fail=1
    fi
done
exit $fail
