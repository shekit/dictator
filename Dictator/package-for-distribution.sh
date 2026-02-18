#!/bin/bash
# Package Dictator for distribution.
# Creates both DMG and ZIP. If signing/notary settings are provided,
# signs the app and notarizes/staples the DMG.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_NAME="Dictator"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
VERSION="1.0.0"
DIST_DIR="$SCRIPT_DIR/dist"
LOCAL_SIGNING_CONFIG="$SCRIPT_DIR/signing.local.env"

# Optional runtime config (do NOT commit secrets)
# Supports:
#   DICTATOR_CODESIGN_IDENTITY="Developer ID Application: ... (TEAMID)"
#   DICTATOR_NOTARY_PROFILE="dictator-notary"
if [ -f "$LOCAL_SIGNING_CONFIG" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$LOCAL_SIGNING_CONFIG"
    set +a
fi

CODESIGN_IDENTITY="${DICTATOR_CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${DICTATOR_NOTARY_PROFILE:-}"

usage() {
    cat <<EOF
Usage: ./package-for-distribution.sh [options]

Options:
  --sign-identity "<identity>"   Override code signing identity
  --notary-profile "<profile>"   Override notarytool keychain profile
  --skip-sign                    Skip code signing
  --skip-notarize                Skip notarization/stapling
  -h, --help                     Show this help

Config from env (or $LOCAL_SIGNING_CONFIG):
  DICTATOR_CODESIGN_IDENTITY
  DICTATOR_NOTARY_PROFILE
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign-identity)
            [ $# -ge 2 ] || { echo "Missing value for --sign-identity"; exit 1; }
            CODESIGN_IDENTITY="$2"
            shift 2
            ;;
        --notary-profile)
            [ $# -ge 2 ] || { echo "Missing value for --notary-profile"; exit 1; }
            NOTARY_PROFILE="$2"
            shift 2
            ;;
        --skip-sign)
            CODESIGN_IDENTITY=""
            shift
            ;;
        --skip-notarize)
            NOTARY_PROFILE=""
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if [ -n "$NOTARY_PROFILE" ] && [ -z "$CODESIGN_IDENTITY" ]; then
    echo "⚠️  Notarization requested without signing identity."
    echo "   DMG notarization is likely to fail unless app is already properly signed."
fi

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

# Step 3: Code signing (optional, recommended)
if [ -n "$CODESIGN_IDENTITY" ]; then
    echo "🔐 Code signing app..."
    echo "   Identity: $CODESIGN_IDENTITY"
    codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
    echo "✅ App signed and verified"
    echo ""
else
    echo "⚠️  Skipping code signing (no identity configured)"
    echo ""
fi

# Step 4: Create distribution directory
echo "📁 Creating distribution directory..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Step 5: Create ZIP file
echo "📦 Creating ZIP archive..."
cd "$SCRIPT_DIR"
ZIP_FILE="$DIST_DIR/$APP_NAME-v$VERSION.zip"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_FILE"
echo "✅ ZIP created: $ZIP_FILE"
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
hdiutil info | grep "$DIST_DIR" | grep "image-path" | sed 's/.*image-path[[:space:]]*:[[:space:]]*//' | while read -r image_path; do
    STALE_DEV=$(hdiutil info | grep -B 10 "image-path.*$image_path" | grep "^/dev/" | head -1 | awk '{print $1}')
    if [ -n "$STALE_DEV" ]; then
        echo "  Detaching $STALE_DEV (from $image_path)..."
        hdiutil detach "$STALE_DEV" -force 2>/dev/null || true
    fi
done

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
3. Follow onboarding to grant permissions

Requirements:
- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac

Usage:
- Hold fn key, speak, release
- Text appears at your cursor
- Configure in menu bar settings
EOF

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

hdiutil convert "$DMG_TEMP" -format UDZO -o "$DMG_FINAL"
rm "$DMG_TEMP"

echo "✅ DMG created: $DMG_FINAL"
echo ""

# Step 7: Notarize + staple DMG (optional, recommended)
if [ -n "$NOTARY_PROFILE" ]; then
    echo "📝 Submitting DMG for notarization..."
    echo "   Profile: $NOTARY_PROFILE"
    xcrun notarytool submit "$DMG_FINAL" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "📎 Stapling notarization ticket..."
    xcrun stapler staple "$DMG_FINAL"
    xcrun stapler validate "$DMG_FINAL"
    echo "✅ DMG notarized and stapled"
    echo ""
else
    echo "⚠️  Skipping notarization (no notary profile configured)"
    echo ""
fi

# Step 8: Calculate file sizes
ZIP_SIZE=$(du -h "$ZIP_FILE" | cut -f1)
DMG_SIZE=$(du -h "$DMG_FINAL" | cut -f1)

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Distribution packages ready!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📦 ZIP Archive ($ZIP_SIZE):"
echo "   $ZIP_FILE"
echo ""
echo "💿 DMG Image ($DMG_SIZE):"
echo "   $DMG_FINAL"
echo ""
if [ -n "$NOTARY_PROFILE" ]; then
    echo "✅ DMG is signed, notarized, and stapled."
else
    echo "⚠️  DMG is not notarized. Recipients may see Gatekeeper warnings."
fi
echo ""
