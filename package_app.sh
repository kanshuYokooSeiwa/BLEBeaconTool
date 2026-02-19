#!/bin/bash
set -e

# Configuration
APP_NAME="BLEBeaconTool"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
INFO_PLIST="BLEBeaconTool/Info.plist"
ENTITLEMENTS="BLEBeaconTool/BLEBeaconTool.entitlements"
BINARY_SOURCE="ble-beacon-tool"

# Check if binary exists
if [ ! -f "$BINARY_SOURCE" ]; then
    echo "❌ Binary '$BINARY_SOURCE' not found. Please build it first."
    exit 1
fi

echo "📦 Packaging $APP_NAME..."

# Create directory structure
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"

# Copy binary
cp "$BINARY_SOURCE" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# Copy Info.plist
cp "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"

# Create PkgInfo
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

echo "✅ Created App Bundle structure"

# Sign the app bundle
echo "🔐 Signing App Bundle..."
codesign --force --options runtime --deep --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"

echo "✨ Done! App Bundle created at: $APP_BUNDLE"
echo "👉 usage: ./$APP_BUNDLE/Contents/MacOS/$APP_NAME status"
