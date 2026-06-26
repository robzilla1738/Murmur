#!/usr/bin/env bash
# Archive + export a Developer ID-signed, hardened-runtime Murmur.app.
# Does NOT notarize — run scripts/notarize.sh next (you submit to Apple yourself).
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Murmur"
BUILD_DIR="build"

xcodegen generate

rm -rf "$BUILD_DIR/$APP_NAME.xcarchive" "$BUILD_DIR/export"

echo "▸ Archiving (Release)…"
xcodebuild -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    archive \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive"

echo "▸ Exporting Developer ID app…"
xcodebuild -exportArchive \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    -exportPath "$BUILD_DIR/export" \
    -exportOptionsPlist ExportOptions.plist

echo "✅ Exported $BUILD_DIR/export/$APP_NAME.app"
codesign -dv --verbose=4 "$BUILD_DIR/export/$APP_NAME.app" 2>&1 | grep -E "Authority|Runtime|Identifier" || true
echo "Next: scripts/notarize.sh  (you run this — it submits to Apple)"
