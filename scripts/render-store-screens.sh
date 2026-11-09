#!/usr/bin/env bash
set -euo pipefail

# Render the App Store screenshot set from design/appstore-v2/screens.html to
# 2560x1600 PNGs with headless Chrome (the glass needs a real browser's
# backdrop-filter, which the old AppKit renderer could not do).
# Usage: bash scripts/render-store-screens.sh [output-dir]   (default store/screenshots)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/store/screenshots}"
SRC="$ROOT/design/appstore-v2/screens.html"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
COUNT=5

mkdir -p "$OUT"
PROFILE="$(mktemp -d "$ROOT/.build/chrome-profile.XXXXXX")"
trap 'rm -rf "$PROFILE"' EXIT

for n in $(seq 1 "$COUNT"); do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --user-data-dir="$PROFILE" --allow-file-access-from-files \
    --window-size=2560,1600 --virtual-time-budget=2000 \
    --screenshot="$OUT/screenshot-$n.png" "file://$SRC#$n" >/dev/null 2>&1
  echo "✓ $OUT/screenshot-$n.png"
done
