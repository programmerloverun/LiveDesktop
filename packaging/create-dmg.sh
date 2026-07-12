#!/bin/bash
# Create a DMG with app shortcut and background
set -e

APP_PATH="$1"
DMG_PATH="$2"
VOL_NAME="LiveDesktop"

if [ -z "$APP_PATH" ] || [ -z "$DMG_PATH" ]; then
    echo "Usage: $0 <app-bundle> <output.dmg>"
    exit 1
fi

TMP_DMG="/tmp/LiveDesktop_tmp.dmg"
TMP_MOUNT="/tmp/LiveDesktop_mount"
OUT_DMG="$DMG_PATH"

rm -f "$TMP_DMG" "$OUT_DMG"
mkdir -p "$TMP_MOUNT"

# Create read-write DMG
hdiutil create -size 100m -volname "$VOL_NAME" -fs HFS+ -attach "$TMP_DMG"

# Copy app
cp -R "$APP_PATH" "/Volumes/$VOL_NAME/"

# Create Applications symlink
ln -s /Applications "/Volumes/$VOL_NAME/Applications"

# Set icon positions
osascript -e "
tell application \"Finder\"
    tell disk \"$VOL_NAME\"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 200, 600, 480}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 80
        set position of item \"$(basename "$APP_PATH")\" to {120, 140}
        set position of item \"Applications\" to {280, 140}
        close
    end tell
end tell
" 2>/dev/null || true

# Detach
hdiutil detach "/Volumes/$VOL_NAME" -force

# Convert to compressed read-only
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG"
rm -f "$TMP_DMG"

echo "DMG created: $OUT_DMG"
ls -lh "$OUT_DMG"
