#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="TinyRazer"
BUNDLE_NAME="Tiny Razer"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="$BUILD_DIR/$BUNDLE_NAME.app"
ENTITLEMENTS="$ROOT_DIR/Resources/TinyRazer.entitlements"

# Code-signing identity resolution, in priority order:
#   1. $CODESIGN_IDENTITY env var    (explicit override)
#   2. First "Developer ID Application: …"  (distribution / notarization-ready)
#   3. First "Apple Development: …"  (stable across rebuilds — preserves TCC grants)
#   4. "Tiny Razer Dev"              (persistent self-signed from scripts/setup-dev-identity.sh)
#   5. "-"                            (ad-hoc; TCC permissions lost on every rebuild)
resolve_identity() {
    if [ -n "${CODESIGN_IDENTITY:-}" ]; then
        echo "$CODESIGN_IDENTITY"
        return
    fi
    local identities
    identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

    local match
    match="$(echo "$identities" | grep -o '"Developer ID Application: [^"]*"' | head -n1 | tr -d '"')"
    if [ -n "$match" ]; then echo "$match"; return; fi

    match="$(echo "$identities" | grep -o '"Apple Development: [^"]*"' | head -n1 | tr -d '"')"
    if [ -n "$match" ]; then echo "$match"; return; fi

    match="$(echo "$identities" | grep -o '"Tiny Razer Dev"' | head -n1 | tr -d '"')"
    if [ -n "$match" ]; then echo "$match"; return; fi

    echo "-"
}

IDENTITY="$(resolve_identity)"

echo "==> Building ($CONFIG)"
cd "$ROOT_DIR"
swift build -c "$CONFIG" --product "$APP_NAME"

BIN_PATH=$(swift build -c "$CONFIG" --show-bin-path)

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Hardened runtime + entitlements are required for notarization. For ad-hoc
# and self-signed builds the extra flags are harmless.
echo "==> Codesign (identity: $IDENTITY)"
SIGN_ARGS=(--force --deep --options runtime --timestamp --sign "$IDENTITY")
if [ -f "$ENTITLEMENTS" ]; then
    SIGN_ARGS+=(--entitlements "$ENTITLEMENTS")
fi
codesign "${SIGN_ARGS[@]}" "$APP_DIR"

echo "==> Verify"
codesign --verify --deep --strict --verbose=2 "$APP_DIR" 2>&1 | sed 's/^/    /'

echo "==> Done: $APP_DIR"
if [ "$IDENTITY" = "-" ]; then
    echo "⚠  Ad-hoc signature used. TCC permissions will be lost on every rebuild."
    echo "   Run ./scripts/setup-dev-identity.sh once to fix this."
elif [[ "$IDENTITY" == "Developer ID Application:"* ]]; then
    echo ""
    echo "ℹ  Developer ID signature applied. For Gatekeeper-bypass-free"
    echo "   distribution, notarize with scripts/notarize.sh"
fi
echo "Launch with: open \"$APP_DIR\""
