#!/usr/bin/env bash
set -euo pipefail

# Build a Mac App Store .pkg for upload via Transporter. This sidesteps Xcode's
# Organizer "sending analytics to App Store" hang: it exports the signed .pkg to
# disk and you upload it yourself with Transporter (or altool, see bottom).
#
# Signing is automatic: -allowProvisioningUpdates creates/downloads the App Store
# distribution cert + Mac App Store provisioning profile from your Xcode-logged-in
# account (Xcode > Settings > Accounts must have the paid team, PKUE74YS72).
#
# Bump the version first in project.yml (MARKETING_VERSION / CURRENT_PROJECT_VERSION).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "▸ regenerating project (sandbox + category live in source)…"
command -v xcodegen >/dev/null && xcodegen generate

echo "▸ archiving…"
rm -rf build/TuckBar.xcarchive build/appstore
xcodebuild -project TuckBar.xcodeproj -scheme TuckBar -configuration Release \
  -archivePath build/TuckBar.xcarchive archive

echo "▸ exporting App Store .pkg…"
xcodebuild -exportArchive -archivePath build/TuckBar.xcarchive \
  -exportOptionsPlist scripts/ExportOptions-appstore.plist \
  -exportPath build/appstore -allowProvisioningUpdates

PKG="$ROOT/build/appstore/TuckBar.pkg"
echo ""
echo "✓ App Store package: $PKG"
echo "  installer cert: $(pkgutil --check-signature "$PKG" 2>/dev/null | grep -m1 Installer | sed 's/^ *//')"
echo ""
echo "  Upload via Transporter (drag the .pkg in), or from the CLI:"
echo "    xcrun altool --upload-app -t macos -f \"$PKG\" --apple-id YOU@APPLEID --password APP-SPECIFIC-PW"
