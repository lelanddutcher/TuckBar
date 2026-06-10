#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

echo "▸ rendering icon art…"
swift "$ROOT/scripts/make-icon.swift" "$ICONSET"

echo "▸ iconutil → .icns…"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"

# Keep a 1024 preview alongside the design studies.
cp "$WORK/AppIcon-1024.png" "$ROOT/design/tuckbar-appicon-1024.png" 2>/dev/null || true

rm -rf "$WORK"
echo "✓ wrote $ROOT/Resources/AppIcon.icns"
