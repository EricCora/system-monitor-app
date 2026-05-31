#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="PulseBar"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Remove stale Xcode debug bundles so Spotlight only indexes /Applications.
rm -rf \
    "$ROOT_DIR/.derivedData/Build/Products/Debug/$APP_NAME.app" \
    "$ROOT_DIR/build/DerivedData/Build/Products/Debug/$APP_NAME.app" \
    2>/dev/null || true

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Build a local PulseBar.app bundle from the Swift package products.

Usage:
  ./scripts/package_app.sh
  ./scripts/package_app.sh --dist-only

Options:
  --dist-only   Leave the bundle in dist/ only; do not install to /Applications.
                Default behavior installs to /Applications and removes the dist copy
                so Spotlight shows a single PulseBar app.
EOF
    exit 0
fi

INSTALL_TO_APPLICATIONS=1
if [[ "${1:-}" == "--dist-only" ]]; then
    INSTALL_TO_APPLICATIONS=0
fi

echo "Building release binaries..."
swift build -c release --product PulseBarApp --package-path "$ROOT_DIR"
swift build -c release --product PulseBarPrivilegedHelper --package-path "$ROOT_DIR"

APP_EXECUTABLE="$BUILD_DIR/PulseBarApp"
HELPER_EXECUTABLE="$BUILD_DIR/PulseBarPrivilegedHelper"
RESOURCE_BUNDLE="$BUILD_DIR/PulseBar_PulseBarApp.bundle"
APP_ICON="$ROOT_DIR/PulseBar/Resources/AppIcon.icns"

if [[ ! -x "$APP_EXECUTABLE" ]]; then
    echo "Missing app executable at $APP_EXECUTABLE" >&2
    exit 1
fi

if [[ ! -x "$HELPER_EXECUTABLE" ]]; then
    echo "Missing helper executable at $HELPER_EXECUTABLE" >&2
    exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

xattr -cr "$APP_EXECUTABLE" "$HELPER_EXECUTABLE" 2>/dev/null || true
COPYFILE_DISABLE=1 cp "$APP_EXECUTABLE" "$MACOS_DIR/$APP_NAME"
COPYFILE_DISABLE=1 cp "$HELPER_EXECUTABLE" "$MACOS_DIR/PulseBarPrivilegedHelper"
xattr -cr "$MACOS_DIR"

if [[ -d "$RESOURCE_BUNDLE" ]]; then
    COPYFILE_DISABLE=1 ditto --norsrc --noextattr "$RESOURCE_BUNDLE" "$RESOURCES_DIR/$(basename "$RESOURCE_BUNDLE")"
fi

if [[ -f "$APP_ICON" ]]; then
    COPYFILE_DISABLE=1 cp "$APP_ICON" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>PulseBar</string>
    <key>CFBundleExecutable</key>
    <string>PulseBar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.pulsebar</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PulseBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
find "$APP_BUNDLE" -exec xattr -c {} \; 2>/dev/null || true
xattr -cr "$APP_BUNDLE"

if [[ "$INSTALL_TO_APPLICATIONS" -eq 1 ]]; then
    INSTALL_PATH="/Applications/$APP_NAME.app"
    rm -rf "$INSTALL_PATH"
    COPYFILE_DISABLE=1 ditto --norsrc --noextattr "$APP_BUNDLE" "$INSTALL_PATH"
    rm -rf "$APP_BUNDLE"
    find "$INSTALL_PATH" -exec xattr -c {} \; 2>/dev/null || true
    xattr -cr "$INSTALL_PATH"
    codesign --force --deep --sign - "$INSTALL_PATH"
    echo "Installed app bundle (only copy):"
    echo "  $INSTALL_PATH"
else
    codesign --force --deep --sign - "$APP_BUNDLE"
    echo "Packaged app bundle:"
    echo "  $APP_BUNDLE"
fi
