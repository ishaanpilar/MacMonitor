#!/bin/bash
# Builds a Release MacMonitor.app and packages it into a distributable DMG.
#
# This produces an *ad-hoc signed* (i.e. unsigned for distribution) build. Users will need to
# remove the quarantine attribute on first launch — see the README. To ship a notarized build
# later, set DEVELOPMENT_TEAM in the project and run notarytool before makeDMG.
#
# Usage: scripts/package.sh [output-dir]   (default: ./dist)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist}"
BUILD="$ROOT/.build-release"
APP_NAME="MacMonitor"

rm -rf "$BUILD" "$OUT"
mkdir -p "$OUT"

echo "▸ Building Release…"
xcodebuild \
  -project "$ROOT/$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD" \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

APP="$BUILD/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || { echo "✗ build failed: $APP not found"; exit 1; }

# Building with CODE_SIGNING_ALLOWED=NO leaves an inconsistent signature seal, which makes
# Gatekeeper report the app as "damaged". Re-sign ad-hoc so the seal is valid; downloaded copies
# then get the normal "unidentified developer" prompt (right-click → Open) instead.
echo "▸ Re-signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "  signature valid ✔"

VERSION="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)"
echo "▸ Built $APP_NAME $VERSION"

echo "▸ Creating DMG…"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/$APP_NAME-$VERSION.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "▸ Done: $DMG"
echo "  sha256: $(shasum -a 256 "$DMG" | awk '{print $1}')"
