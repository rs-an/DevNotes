# Sourced by build-app.sh and package-release.sh (zsh).
# Keep both build paths on the same variant, metadata and resource rules.
VARIANT="${1:-app}"
SWIFT_FLAGS=()
case "$VARIANT" in
    app)
        APP_NAME="DevNotes"
        BUNDLE_ID="local.devnotes.app"
        ;;
    demo)
        APP_NAME="DevNotes Demo"
        BUNDLE_ID="local.devnotes.portfolio-demo"
        SWIFT_FLAGS=(-Xswiftc -DDEVNOTES_DEMO)
        ;;
    *) print -u2 "Usage: $0 [app|demo]"; exit 2 ;;
esac

configure_variant_bundle() {
    local bundle="$1"
    cp -X "$PROJECT_DIR/Info.plist" "$bundle/Contents/Info.plist"
    plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$bundle/Contents/Info.plist"
    plutil -replace CFBundleName -string "$APP_NAME" "$bundle/Contents/Info.plist"
    plutil -replace CFBundleDisplayName -string "$APP_NAME" "$bundle/Contents/Info.plist"
    cp -X "$PROJECT_DIR/Assets/AppIcon.png" "$bundle/Contents/Resources/AppIcon.png"
    if [[ "$VARIANT" == demo ]]; then
        cp -X "$PROJECT_DIR/Assets/Demo/IconStudy.png" "$bundle/Contents/Resources/IconStudy.png"
    fi
}
