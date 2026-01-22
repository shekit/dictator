#!/bin/bash
# Build and package Dictator as a macOS .app bundle
# Also resets onboarding state before building
#
# Usage:
#   ./build-app.sh              # Build without clearing models
#   ./build-app.sh --clear-models   # Build and clear models (~443MB re-download)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_NAME="Dictator"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"

# Reset onboarding state first (pass through any flags)
"$SCRIPT_DIR/reset-onboarding.sh" "$@"
echo ""

echo "Building $APP_NAME..."
cd "$SCRIPT_DIR"
swift build -c release

echo "Creating app bundle..."
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
    echo "App icon included"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "App bundle created at: $APP_BUNDLE"
echo "Run with: open $APP_BUNDLE"
