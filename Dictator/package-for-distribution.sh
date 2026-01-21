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

# Create temporary DMG (with extra space for filesystem overhead)
hdiutil create -size 200m -fs HFS+ -volname "$APP_NAME" "$DMG_TEMP"

# Mount the DMG
hdiutil attach "$DMG_TEMP" -mountpoint /Volumes/$APP_NAME

# Copy app to DMG
cp -R "$APP_BUNDLE" "/Volumes/$APP_NAME/"

# Create Applications symlink for easy installation
ln -s /Applications "/Volumes/$APP_NAME/Applications"

# Add README
cat > "/Volumes/$APP_NAME/README.txt" << EOF
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

# Unmount
hdiutil detach "/Volumes/$APP_NAME"

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
