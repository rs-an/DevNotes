#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="${DEVNOTES_APP_OUTPUT:-$PROJECT_DIR/dist/DevNotes.app}"

cd "$PROJECT_DIR"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

SDKROOT="$SDK_PATH" \
CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/swiftpm-cache" \
swift build --disable-sandbox -c release -j 1

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp ".build/release/DevNotes" "$APP_DIR/Contents/MacOS/DevNotes"
cp "Info.plist" "$APP_DIR/Contents/Info.plist"
cp "Assets/AppIcon.png" "$APP_DIR/Contents/Resources/AppIcon.png"
codesign --force --deep --entitlements "$PROJECT_DIR/DevNotes.entitlements" --sign - "$APP_DIR"

echo "$APP_DIR"
