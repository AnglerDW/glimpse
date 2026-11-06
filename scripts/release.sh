#!/bin/bash
# Build a distributable Glimpse: Release, universal (arm64 + x86_64), hardened runtime, signed,
# packaged as Glimpse-<version>.dmg and Glimpse-<version>.zip under dist/, with SHA-256 sums.
#
# Signing, best available first:
#   1. Developer ID Application certificate in the keychain (set RELEASE_SIGN_ID to pick one by
#      name) -> signed with a timestamp; then notarized and stapled when NOTARY_PROFILE names a
#      `xcrun notarytool store-credentials` profile. This is what a public download needs: without
#      notarization macOS 15+ blocks the app on first open until the user allows it in
#      System Settings > Privacy & Security.
#   2. Otherwise ad-hoc ("-"): the app runs, but Gatekeeper warns on first open (README explains
#      the "Open Anyway" step). Screen Recording permission is also tied to the signature, so an
#      ad-hoc build asks for it again after every rebuild.
#
# Usage: scripts/release.sh            # version from project.yml
#        RELEASE_SIGN_ID="Developer ID Application: Name (TEAM)" NOTARY_PROFILE=glimpse scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(awk '/CFBundleShortVersionString/ { gsub(/"/, "", $2); print $2; exit }' project.yml)"
[ -n "$VERSION" ] || { echo "error: CFBundleShortVersionString not found in project.yml" >&2; exit 1; }
DIST="dist"
APP_NAME="Glimpse"
BUILD_DIR="build/release"
APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"

echo "==> Generating project and building $APP_NAME $VERSION (Release, universal)"
xcodegen generate --quiet
xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$BUILD_DIR" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO -quiet build
[ -d "$APP" ] || { echo "error: build product missing: $APP" >&2; exit 1; }

# --- signing identity -------------------------------------------------------------------------
# Prefer a Developer ID certificate; `security find-identity -v` only lists usable (unrevoked,
# unexpired) ones. The name match is a plain substring (RELEASE_SIGN_ID defaults to the Developer ID
# prefix), and the hash is used for signing so two certificates with one name cannot be confused.
WANT="${RELEASE_SIGN_ID:-Developer ID Application}"
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -v name="$WANT" 'index($0, name) { print $2; exit }' || true)"
if [ -n "$IDENTITY" ]; then
  echo "==> Signing with $WANT ($IDENTITY), hardened runtime, timestamp"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  SIGNED=developer-id
else
  echo "warning: no '$WANT' certificate in the keychain; signing ad-hoc. The download will trigger" >&2
  echo "warning: Gatekeeper's 'unidentified developer' flow and cannot be notarized." >&2
  codesign --force --options runtime --timestamp=none --sign - "$APP"
  SIGNED=ad-hoc
fi
codesign --verify --strict --verbose=2 "$APP"
lipo -info "$APP/Contents/MacOS/$APP_NAME"

# --- packaging --------------------------------------------------------------------------------
rm -rf "$DIST" && mkdir -p "$DIST"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="$DIST/$APP_NAME-$VERSION.dmg"
ZIP="$DIST/$APP_NAME-$VERSION.zip"
echo "==> Packaging $DMG and $ZIP"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"

# --- notarization (Developer ID only) -----------------------------------------------------------
if [ "$SIGNED" = developer-id ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "==> Notarizing with keychain profile '$NOTARY_PROFILE'"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  # A .zip cannot be stapled; the ticket inside the .app is what counts. Re-zip the stapled app.
  xcrun stapler staple "$APP"
  ditto -c -k --keepParent "$APP" "$ZIP"
elif [ "$SIGNED" = developer-id ]; then
  echo "note: NOTARY_PROFILE not set; skipped notarization." >&2
fi

(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" | tee SHA256SUMS.txt)
echo "==> Done: $DIST ($SIGNED)"
