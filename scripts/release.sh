#!/usr/bin/env bash
set -euo pipefail

# Build, sign (Developer ID), notarize, and staple TuckBar for distribution
# outside the App Store. Produces a notarized, Gatekeeper-clean .zip you can
# attach to a GitHub release or host on the site.
#
# One-time setup:
#   1. Developer ID Application cert in your login keychain (already present).
#   2. A notarytool credential profile, stored once in your keychain:
#        xcrun notarytool store-credentials "TuckBar-Notary" \
#          --apple-id "you@appleid.com" --team-id PKUE74YS72 \
#          --password <app-specific-password>
#      (an app-specific password is created at appleid.apple.com -> Sign-In & Security.
#       Or use an App Store Connect API key: --key / --key-id / --issuer.)
#
# Then just: ./scripts/release.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NOTARY_PROFILE="${NOTARY_PROFILE:-TuckBar-Notary}"
BUILD="$ROOT/build"
ARCHIVE="$BUILD/TuckBar.xcarchive"
EXPORT="$BUILD/export"
APP="$EXPORT/TuckBar.app"

echo "▸ regenerating project from project.yml…"
command -v xcodegen >/dev/null && xcodegen generate

echo "▸ archiving (Release · Developer ID · hardened runtime)…"
rm -rf "$ARCHIVE" "$EXPORT"
xcodebuild -project TuckBar.xcodeproj -scheme TuckBar -configuration Release \
  -archivePath "$ARCHIVE" archive

echo "▸ exporting the Developer ID app…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist" \
  -exportPath "$EXPORT"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ZIP="$BUILD/TuckBar.zip"
DIST="$BUILD/TuckBar-$VERSION.zip"

echo "▸ zipping for notarization…"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ submitting to Apple notary (waits for the verdict)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▸ stapling the ticket onto the app…"
xcrun stapler staple "$APP"

echo "▸ repackaging the stapled app for release…"
rm -f "$DIST"
ditto -c -k --keepParent "$APP" "$DIST"

echo ""
echo "✓ done"
echo "  notarized app : $APP"
echo "  shippable zip : $DIST"
echo "  gatekeeper    : spctl -a -vvv --type exec \"$APP\""
