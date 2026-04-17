#!/usr/bin/env bash
set -euo pipefail

# Reset the Input Monitoring TCC grant for Tiny Razer and relaunch.
# Useful after unexpected permission loss.

BUNDLE_ID="com.hyunseokbyun.tinyrazer"

echo "==> Stopping Tiny Razer"
pkill -f TinyRazer 2>/dev/null || true
sleep 1

echo "==> Resetting Input Monitoring permission"
tccutil reset ListenEvent "$BUNDLE_ID"

echo "==> Relaunching"
APP_PATH="$(cd "$(dirname "$0")/.." && pwd)/.build/Tiny Razer.app"
if [ -d "$APP_PATH" ]; then
    open "$APP_PATH"
    echo "✓ Relaunched. Menu bar will prompt for permission again."
else
    echo "App not built yet. Run ./build-app.sh release first."
fi
