#!/bin/bash
# Builds dist/Hanare.app and dist/Hanare-<version>.zip.
#
# The app is signed with the identity named by SIGN_IDENTITY, or with "Hanare Local Signing" if the
# keychain has one, and ad-hoc otherwise. macOS ties permissions such as Accessibility to the
# signature, so a stable identity keeps them across rebuilds; an ad-hoc signature changes with
# every build and the permissions have to be granted again. To create an identity,
# use Keychain Access > Certificate Assistant > Create a Certificate (type: Code Signing).
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
COMMIT="${COMMIT:-$(git rev-parse --short=9 HEAD 2>/dev/null || echo unknown)}"
APP="dist/Hanare.app"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Hanare" "$APP/Contents/MacOS/Hanare"
# Flatten the SwiftPM resource bundle into the app so resources load from Bundle.main.
cp -R "$BIN_DIR/Hanare_Hanare.bundle/Contents/Resources/." "$APP/Contents/Resources/"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/\$(VERSION)/$VERSION/" -e "s/\$(BUILD_NUMBER)/$BUILD_NUMBER/" -e "s/\$(COMMIT)/$COMMIT/" Support/Info.plist > "$APP/Contents/Info.plist"

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-identity -p codesigning | grep -q '"Hanare Local Signing"'; then
    IDENTITY="Hanare Local Signing"
fi
echo "Signing with: ${IDENTITY:-ad-hoc}"
codesign --force --sign "${IDENTITY:--}" "$APP"
ditto -c -k --keepParent "$APP" "dist/Hanare-$VERSION.zip"
echo "Built $APP and dist/Hanare-$VERSION.zip"
