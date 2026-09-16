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

# If ble-beacon-tool doesn't exist in root, check Xcode DerivedData
if [ ! -f "$BINARY_SOURCE" ]; then
    XCODE_BUILD_BIN=$(find ~/Library/Developer/Xcode/DerivedData/BLEBeaconTool-*/Build/Products/Release/BLEBeaconTool 2>/dev/null | head -n 1 || true)
    if [ -n "$XCODE_BUILD_BIN" ] && [ -f "$XCODE_BUILD_BIN" ]; then
        echo "Found Xcode build artifact at: $XCODE_BUILD_BIN"
        cp "$XCODE_BUILD_BIN" "$BINARY_SOURCE"
    fi
fi

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
# Extract the authority (identity) from the built binary
IDENTITY=$(codesign -dvv "$BINARY_SOURCE" 2>&1 | grep "Authority=" | head -n 1 | cut -d= -f2 || true)
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
fi
if [ -z "$IDENTITY" ]; then
    IDENTITY="-"
fi
echo "Using Identity: $IDENTITY"

# Sign inner binary with entitlements
codesign --force --options runtime --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$MACOS_DIR/$APP_NAME"

# Sign bundle with entitlements
codesign --force --options runtime --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"

echo "🔍 Verifying signature..."
codesign -vvv --strict "$APP_BUNDLE"

echo "✨ Done! App Bundle created at: $APP_BUNDLE"
echo "👉 usage: ./$APP_BUNDLE/Contents/MacOS/$APP_NAME status"
echo "👉 advertise: ./$APP_BUNDLE/Contents/MacOS/$APP_NAME advertise --uuid 92821D61-9FEE-4003-87F1-31799E12017A --major 1 --minor 1"
