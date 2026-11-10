#!/usr/bin/env bash
set -euo pipefail

# Render the App Store screenshot set from design/appstore-v2/screens.html to
# 2560x1600 PNGs with headless Chrome (the glass needs a real browser's
# backdrop-filter, which the old AppKit renderer could not do).
# Usage: bash scripts/render-store-screens.sh [output-dir] [theme] [scale]
#   theme: dawn (default) | daylight | oled
#   scale: 1 = 2560x1600 (default), 1.125 = 2880x1800. Both are Apple's Mac sizes (16:10).
# Output is flattened (no alpha) and tagged sRGB, which App Store Connect requires.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/store/screenshots}"
SRC="$ROOT/design/appstore-v2/screens.html"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
THEME="${2:-dawn}"
SCALE="${3:-1}"
COUNT=5

mkdir -p "$OUT"
PROFILE="$(mktemp -d "$ROOT/.build/chrome-profile.XXXXXX")"
trap 'rm -rf "$PROFILE"' EXIT

for n in $(seq 1 "$COUNT"); do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor="$SCALE" \
    --user-data-dir="$PROFILE" --allow-file-access-from-files \
    --window-size=2560,1600 --virtual-time-budget=2000 \
    --screenshot="$OUT/screenshot-$n.png" "file://$SRC#$n/$THEME" >/dev/null 2>&1
  # flatten to opaque RGB and tag sRGB (sips keeps the pixels, drops alpha via JPEG round trip)
  sips -s format jpeg -s formatOptions 95 --matchTo "/System/Library/ColorSync/Profiles/sRGB Profile.icc" \
    "$OUT/screenshot-$n.png" --out "$OUT/screenshot-$n.jpg" >/dev/null
  sips -s format png "$OUT/screenshot-$n.jpg" --out "$OUT/screenshot-$n.png" >/dev/null
  echo "✓ $OUT/screenshot-$n.png ($(sips -g pixelWidth -g pixelHeight "$OUT/screenshot-$n.png" | awk '/pixel/{printf "%s ", $2}'))"
done
