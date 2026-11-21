#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
source "$SCRIPT_DIR/build-variant.sh" "${1:-app}"
APP_DIR="${DEVNOTES_APP_OUTPUT:-$PROJECT_DIR/dist/$APP_NAME.app}"
[[ "$APP_DIR" == *.app ]] || { print -u2 "Output must end in .app"; exit 2; }
# Refuse to remove an unrelated directory when replacing an existing build.
if [[ -e "$APP_DIR" ]]; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Contents/Info.plist")"
    [[ "$existing_id" == "$BUNDLE_ID" ]] || { print -u2 "Output belongs to another app"; exit 2; }
fi

cd "$PROJECT_DIR"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/swiftpm-cache"
build_args=(--scratch-path "$PROJECT_DIR/.build/$VARIANT" --disable-sandbox -c release -j 1 "${SWIFT_FLAGS[@]}")
swift build "${build_args[@]}"
BIN_DIR="$(swift build "${build_args[@]}" --show-bin-path)"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devnotes-app.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
BUNDLE="$STAGING_DIR/$APP_NAME.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_DIR/DevNotes" "$BUNDLE/Contents/MacOS/DevNotes"
configure_variant_bundle "$BUNDLE"
codesign --force --deep --entitlements "$PROJECT_DIR/DevNotes.entitlements" --sign - "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
mkdir -p "${APP_DIR:h}"
if [[ -e "$APP_DIR" ]]; then rm -rf "$APP_DIR"; fi
ditto "$BUNDLE" "$APP_DIR"
echo "$APP_DIR"
