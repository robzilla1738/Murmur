#!/usr/bin/env bash
# Notarize + staple the exported Murmur.app, then verify with Gatekeeper.
# Requires a one-time `xcrun notarytool store-credentials AC_PASSWORD …`.
# Run this yourself — it submits your binary to Apple's notary service.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Murmur"
BUILD_DIR="build"
APP="$BUILD_DIR/export/$APP_NAME.app"
PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"

if [ ! -d "$APP" ]; then
    echo "No app at $APP. Run scripts/build-release.sh first." >&2
    exit 1
fi

echo "▸ Zipping for notarization…"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/$APP_NAME.zip"

echo "▸ Submitting to Apple notary (profile: $PROFILE)…"
xcrun notarytool submit "$BUILD_DIR/$APP_NAME.zip" --keychain-profile "$PROFILE" --wait

echo "▸ Stapling ticket…"
xcrun stapler staple "$APP"

echo "▸ Verifying with Gatekeeper…"
spctl --assess --verbose=4 "$APP"
echo "✅ Notarized + stapled. Expected: 'source=Notarized Developer ID', 'accepted'."
echo "Next: scripts/make-dmg.sh"
