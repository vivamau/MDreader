#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
BUILD_NUMBER="${2:-1}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Use a semantic version such as 0.1.0' >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || exit 1
OUT="$ROOT/dist"
WORK="$(mktemp -d /tmp/MDReader-release.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT" "$WORK/staging"
xcodebuild -project "$ROOT/MDReader.xcodeproj" -scheme MDReader -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "${MDREADER_RELEASE_DERIVED_DATA:-/tmp/MDReader-release-build}" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" build
APP="$WORK/staging/MDReader.app"
ditto "${MDREADER_RELEASE_DERIVED_DATA:-/tmp/MDReader-release-build}/Build/Products/Release/MDReader.app" "$APP"
# Preserve the app sandbox entitlements in the ad-hoc signature.
codesign --force --sign - --options runtime --entitlements "$ROOT/MDReader/MDReader.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
lipo "$APP/Contents/MacOS/MDReader" -verify_arch arm64
lipo "$APP/Contents/MacOS/MDReader" -verify_arch x86_64
ln -s /Applications "$WORK/staging/Applications"
cat > "$WORK/staging/Read Me.txt" <<TEXT
MDReader $VERSION (build $BUILD_NUMBER)
Requires macOS 14 or later. Supports Apple Silicon and Intel.
Drag MDReader.app to Applications.
This preview build is ad-hoc signed, not Developer ID signed or notarized.
Source: https://github.com/vivamau/MDreader
TEXT
DMG="$OUT/MDReader-$VERSION-macOS-universal.dmg"
hdiutil create -volname "MDReader $VERSION" -srcfolder "$WORK/staging" -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Created $DMG"
