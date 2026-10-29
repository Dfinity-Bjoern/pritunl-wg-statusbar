#!/bin/bash
# Builds PritunlWG.app from the Swift sources.
# Usage: bash build.sh [--install]
#   --install  also copies the .app to /Applications after building
set -euo pipefail

APP="PritunlWG"
BUILD="$(dirname "$0")/build"
APP_DIR="$BUILD/$APP.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

HERE="$(cd "$(dirname "$0")" && pwd)"
SOURCES=(
    "$HERE/Sources/main.swift"
    "$HERE/Sources/AppDelegate.swift"
    "$HERE/Sources/ConnectionState.swift"
    "$HERE/Sources/StatusManager.swift"
    "$HERE/Sources/VPNController.swift"
    "$HERE/Sources/StatusIcon.swift"
    "$HERE/Sources/MenuController.swift"
    "$HERE/Sources/LogViewer.swift"
)

echo "==> Creating bundle structure"
mkdir -p "$MACOS" "$RESOURCES"

echo "==> Compiling Swift sources"
swiftc -O \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework AppKit \
    -framework Foundation \
    "${SOURCES[@]}" \
    -o "$MACOS/$APP"

echo "==> Copying resources"
cp "$HERE/Info.plist" "$CONTENTS/"
cp "$HERE/Resources/pritunl-wg" "$RESOURCES/"
cp "$HERE/Resources/install.sh" "$RESOURCES/"
chmod +x "$RESOURCES/pritunl-wg" "$RESOURCES/install.sh"

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP_DIR"

echo ""
echo "Built: $APP_DIR"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> Installing to /Applications"
    rm -rf "/Applications/$APP.app"
    cp -r "$APP_DIR" "/Applications/$APP.app"
    echo "Installed. Launch from Applications or:"
    echo "  open /Applications/$APP.app"
else
    echo "To install:  bash build.sh --install"
    echo "To run now:  open '$APP_DIR'"
fi
