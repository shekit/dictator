#!/bin/bash
# Package Dictator for distribution to friends
# Creates both a DMG and ZIP file for easy sharing

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_NAME="Dictator"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
VERSION="1.0.0"
DIST_DIR="$SCRIPT_DIR/dist"

echo "🚀 Packaging $APP_NAME v$VERSION for distribution..."
echo ""

# Step 1: Build release version
echo "📦 Building release version..."
cd "$SCRIPT_DIR"
swift build -c release

# Step 2: Create app bundle
echo "🔨 Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist
cp "$SCRIPT_DIR/Sources/Dictator/Info.plist" "$APP_BUNDLE/Contents/"

# Copy app icon if it exists
if [ -f "$SCRIPT_DIR/Sources/Dictator/Resources/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/Sources/Dictator/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
    echo "✅ App icon included"
else
    echo "⚠️  No app icon found (optional)"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "✅ App bundle created at: $APP_BUNDLE"
echo ""

# Step 3: Code signing (optional)
# Uncomment the following lines if you have a Developer ID certificate
# echo "🔐 Code signing..."
# codesign --force --deep --sign "Developer ID Application: Your Name" "$APP_BUNDLE"
# echo "✅ App signed"
# echo ""

# Step 4: Create distribution directory
echo "📁 Creating distribution directory..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Step 5: Create ZIP file
echo "📦 Creating ZIP archive..."
cd "$SCRIPT_DIR"
ditto -c -k --keepParent "$APP_BUNDLE" "$DIST_DIR/$APP_NAME-v$VERSION.zip"
echo "✅ ZIP created: $DIST_DIR/$APP_NAME-v$VERSION.zip"
echo ""

# Step 6: Create DMG file
echo "💿 Creating DMG image..."
DMG_TEMP="$DIST_DIR/temp.dmg"
DMG_FINAL="$DIST_DIR/$APP_NAME-v$VERSION.dmg"

# Safe cleanup of any stale mounts from THIS project only
echo "🧹 Cleaning up any previous disk images..."

# Only detach volume if it's exactly named "Dictator" (our app)
if [ -d "/Volumes/$APP_NAME" ]; then
    echo "  Detaching /Volumes/$APP_NAME..."
    hdiutil detach "/Volumes/$APP_NAME" -force 2>/dev/null || true
fi

# Only detach images that match our specific dist directory paths
hdiutil info | grep "$DIST_DIR" | grep "image-path" | sed 's/.*image-path[[:space:]]*:[[:space:]]*//' | while read image_path; do
    # Get the device node for this specific image
    STALE_DEV=$(hdiutil info | grep -B 10 "image-path.*$image_path" | grep "^/dev/" | head -1 | awk '{print $1}')
    if [ -n "$STALE_DEV" ]; then
        echo "  Detaching $STALE_DEV (from $image_path)..."
        hdiutil detach "$STALE_DEV" -force 2>/dev/null || true
    fi
done

# Remove old temp.dmg if it exists
rm -f "$DMG_TEMP"

sleep 1

# Create temporary DMG (with extra space for filesystem overhead)
hdiutil create -size 200m -fs HFS+ -volname "$APP_NAME" "$DMG_TEMP"

# Mount the DMG and capture the device node
MOUNT_POINT="/Volumes/$APP_NAME"
echo "📀 Mounting disk image..."
ATTACH_OUTPUT=$(hdiutil attach "$DMG_TEMP" -mountpoint "$MOUNT_POINT" -nobrowse)
DEVICE_NODE=$(echo "$ATTACH_OUTPUT" | grep "^/dev/" | head -1 | awk '{print $1}')
echo "  Mounted at: $MOUNT_POINT ($DEVICE_NODE)"

# Copy app to DMG
cp -R "$APP_BUNDLE" "$MOUNT_POINT/"

# Create Applications symlink for easy installation
ln -s /Applications "$MOUNT_POINT/Applications"

# Add README
cat > "$MOUNT_POINT/README.txt" << EOF
Dictator - Voice-to-Text with AI Cleanup
=========================================

Installation:
1. Drag Dictator.app to the Applications folder
2. Open Dictator from Applications
3. Follow the onboarding to grant permissions

Requirements:
- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac

Usage:
- Hold fn key, speak, release
- Text appears at your cursor
- Configure in menu bar settings

For more info: https://github.com/yourusername/dictator
EOF

# Force sync to ensure all writes are flushed
sync
echo "⏳ Flushing writes to disk..."
sleep 2

# Unmount using the device node (more reliable than mount point)
echo "📤 Ejecting disk image ($DEVICE_NODE)..."
RETRIES=5
for i in $(seq 1 $RETRIES); do
    if hdiutil detach "$DEVICE_NODE" 2>/dev/null; then
        echo "✅ Disk image ejected"
        break
    else
        if [ $i -eq $RETRIES ]; then
            echo "⚠️  Normal eject failed, forcing..."
            hdiutil detach "$DEVICE_NODE" -force || {
                echo "❌ Force eject failed. Trying mount point..."
                hdiutil detach "$MOUNT_POINT" -force || true
            }
        else
            echo "⏳ Retrying eject ($i/$RETRIES)..."
            sleep 1
        fi
    fi
done

# Convert to compressed DMG
hdiutil convert "$DMG_TEMP" -format UDZO -o "$DMG_FINAL"
rm "$DMG_TEMP"

echo "✅ DMG created: $DMG_FINAL"
echo ""

# Step 7: Calculate file sizes
ZIP_SIZE=$(du -h "$DIST_DIR/$APP_NAME-v$VERSION.zip" | cut -f1)
DMG_SIZE=$(du -h "$DMG_FINAL" | cut -f1)

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Distribution packages ready!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📦 ZIP Archive ($ZIP_SIZE):"
echo "   $DIST_DIR/$APP_NAME-v$VERSION.zip"
echo ""
echo "💿 DMG Image ($DMG_SIZE):"
echo "   $DMG_FINAL"
echo ""
echo "📤 Share these files with your friends!"
echo ""
echo "⚠️  Note: Apps distributed outside the App Store may show"
echo "   a security warning. Recipients should:"
echo "   1. Right-click the app → Open (first time only)"
echo "   2. Click 'Open' in the security dialog"
echo ""
