#!/usr/bin/env bash
set -euo pipefail

# Notarize and staple the .app bundle built by build-app.sh.
#
# One-time setup (stores credentials in your keychain so you never type the
# app-specific password again):
#
#   xcrun notarytool store-credentials "tiny-razer-notary" \
#       --apple-id "your@apple.id" \
#       --team-id "YOUR_TEAM_ID" \
#       --password "app-specific-password-from-appleid.apple.com"
#
# Then just: ./scripts/notarize.sh

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT_DIR/.build/Tiny Razer.app"
KEYCHAIN_PROFILE="${NOTARY_PROFILE:-tiny-razer-notary}"

if [ ! -d "$APP" ]; then
    echo "error: $APP not found — build first with ./build-app.sh release"
    exit 1
fi

echo "==> Verifying signature before submission"
codesign --verify --deep --strict --verbose=2 "$APP" || {
    echo "error: app isn't properly signed. Rebuild with ./build-app.sh release"
    exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ZIP="$TMP/TinyRazer-notarize.zip"

echo "==> Packaging for submission"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting to Apple (this can take a few minutes)"
xcrun notarytool submit "$ZIP" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

echo "==> Stapling the ticket onto the bundle"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "✓ Notarized. Gatekeeper will now open the app without the right-click dance."
