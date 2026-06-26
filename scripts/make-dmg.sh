#!/usr/bin/env bash
# Package the (notarized) Murmur.app into a distributable DMG and staple it.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Murmur"
BUILD_DIR="build"
APP="$BUILD_DIR/export/$APP_NAME.app"

if [ ! -d "$APP" ]; then
    echo "No app at $APP. Run scripts/build-release.sh first." >&2
    exit 1
fi
if ! command -v create-dmg >/dev/null 2>&1; then
    echo "create-dmg not found. Install with: brew install create-dmg" >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"

create-dmg \
    --volname "$APP_NAME" \
    --window-size 540 380 \
    --icon-size 110 \
    --icon "$APP_NAME.app" 150 190 \
    --app-drop-link 390 190 \
    "$DMG" "$APP"

# Staple the ticket onto the DMG too (works offline). Ignored if not notarized.
xcrun stapler staple "$DMG" 2>/dev/null || echo "(DMG not stapled — notarize the app first for offline Gatekeeper)"
echo "✅ Created $DMG"
