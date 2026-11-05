#!/bin/sh
# Points the Homebrew cask at a release: writes the version and the SHA-256 of
# dist/Hanare-<version>.zip into Casks/hanare.rb of a local homebrew-tap clone.
#
#   VERSION=0.1.0 ./scripts/update-cask.sh ../homebrew-tap
set -eu

TAP="${1:?usage: VERSION=<version> $0 <path to homebrew-tap>}"
VERSION="${VERSION:?set VERSION, e.g. VERSION=0.1.0}"
ZIP="dist/Hanare-$VERSION.zip"
CASK="$TAP/Casks/hanare.rb"

[ -f "$ZIP" ] || { echo "Missing $ZIP. Run VERSION=$VERSION ./scripts/build-app.sh first." >&2; exit 1; }
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
echo "Updated $CASK to $VERSION ($SHA)"
