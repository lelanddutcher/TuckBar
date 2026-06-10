#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="TuckBar"
CONFIG="${CONFIG:-release}"
APP_BUNDLE="$ROOT/build/$APP_NAME.app"

echo "▸ swift build (-c $CONFIG)…"
cd "$ROOT"
swift build -c "$CONFIG"

BIN="$ROOT/.build/$CONFIG/$APP_NAME"
[ -f "$BIN" ] || { echo "✗ binary not found at $BIN"; exit 1; }

echo "▸ assembling $APP_NAME.app…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "▸ ad-hoc codesign…"
codesign --force --sign - "$APP_BUNDLE" >/dev/null 2>&1 || echo "  (codesign skipped)"

echo "✓ built $APP_BUNDLE"
echo "  run:  open \"$APP_BUNDLE\""
