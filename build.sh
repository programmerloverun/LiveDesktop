#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="XiaoLeiWallpaper"
BUNDLE_NAME="小雷壁纸.app"
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="$BUILD_DIR/$BUNDLE_NAME"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "=== Building $APP_NAME ==="

# Clean
rm -rf "$APP_DIR"

# Build with SPM
cd "$PROJECT_DIR"
swift build -c release 2>&1

BINARY="$BUILD_DIR/release/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

echo "Binary built: $BINARY"

# Create .app bundle structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary, icon, and resources
cp "$BINARY" "$MACOS_DIR/$APP_NAME"
if [ -f "$PROJECT_DIR/XiaoLeiWallpaper.icns" ]; then
    cp "$PROJECT_DIR/XiaoLeiWallpaper.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
if [ -f "$PROJECT_DIR/Sources/title-icon.png" ]; then
    cp "$PROJECT_DIR/Sources/title-icon.png" "$RESOURCES_DIR/title-icon.png"
fi

# Create Info.plist
cat > "$CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>小雷壁纸</string>
    <key>CFBundleExecutable</key>
    <string>XiaoLeiWallpaper</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.xiaolei.wallpaper</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>XiaoLeiWallpaper</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
EOF

# Create PkgInfo
echo "APPL????" > "$CONTENTS/PkgInfo"

echo ""
echo "=== Build Complete ==="
echo "App: $APP_DIR"
echo ""
echo "To install:"
echo "  cp -R '$APP_DIR' /Applications/"
echo "  open /Applications/$BUNDLE_NAME"
