#!/usr/bin/env bash
#
# Council — sign with Developer ID, notarize with Apple, and staple a distributable
# build for GitHub Releases. Produces build/Council-notarized.zip.
#
# One-time setup (see DISTRIBUTION.md):
#   1. A "Developer ID Application" certificate in your login keychain.
#   2. A stored notarytool credential profile (default name: CouncilNotary).
#
# Usage:
#   TEAM_ID=XXXXXXXXXX ./scripts/notarize.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

# ---- config (override via env) ----
SCHEME="Council"
PROJECT="Council.xcodeproj"
CONFIG="Release"
TEAM_ID="${TEAM_ID:-YOUR_TEAM_ID}"                       # team your Developer ID cert belongs to
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-CouncilNotary}"  # notarytool stored credentials
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/Council.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/Council.app"
ZIP_FOR_NOTARY="$BUILD_DIR/Council-upload.zip"
ZIP_FINAL="$BUILD_DIR/Council-notarized.zip"

echo "▸ Clean"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"

echo "▸ Archive ($CONFIG)"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  archive

echo "▸ Export (Developer ID, hardened runtime, re-signed)"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist scripts/exportOptions.plist \
  -exportPath "$EXPORT_DIR"

echo "▸ Verify signature + hardened runtime + entitlements"
codesign --verify --strict --verbose=2 "$APP"
codesign -d --verbose=4 "$APP" 2>&1 | grep -E "Authority|flags|Runtime" || true
codesign -d --entitlements :- "$APP" 2>/dev/null | plutil -p - 2>/dev/null \
  | grep -E "sandbox|network|user-selected" || true

echo "▸ Zip for notarization"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP_FOR_NOTARY"

echo "▸ Submit to Apple notary service (this waits for the result)"
xcrun notarytool submit "$ZIP_FOR_NOTARY" --keychain-profile "$KEYCHAIN_PROFILE" --wait

echo "▸ Staple the notarization ticket onto the app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "▸ Re-zip the STAPLED app for distribution"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP_FINAL"

echo "▸ Gatekeeper assessment (should say: accepted / Notarized Developer ID)"
spctl -a -vvv --type execute "$APP" || true

echo ""
echo "✓ Done → $ZIP_FINAL  (upload this to GitHub Releases)"
