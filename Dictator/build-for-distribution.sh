#!/bin/bash
# Build Dictator app for distribution with bundled ASR models
# This creates a complete app bundle ready to share with friends

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🎙️  Building Dictator for Distribution"
echo "======================================"
echo ""

# Step 1: Build the app
echo "Step 1/3: Building app..."
"$SCRIPT_DIR/build-app.sh"
echo ""

# Step 2: Bundle models (if available)
echo "Step 2/3: Bundling ASR models..."
if [ -f "$SCRIPT_DIR/bundle-models.sh" ]; then
    "$SCRIPT_DIR/bundle-models.sh" || {
        echo ""
        echo "⚠️  Warning: Could not bundle models."
        echo "The app will download models on first launch (~200MB, takes 2-5 min)."
        echo ""
        echo "To bundle models for offline use:"
        echo "  1. Launch Dictator.app once"
        echo "  2. Wait for models to download"
        echo "  3. Run ./bundle-models.sh"
        echo "  4. Run this script again"
        echo ""
    }
else
    echo "⚠️  bundle-models.sh not found, skipping model bundling"
fi
echo ""

# Step 3: Remove quarantine
echo "Step 3/3: Removing quarantine attribute..."
xattr -cr "$SCRIPT_DIR/Dictator.app"
echo "✓ Quarantine removed"
echo ""

# Summary
APP_SIZE=$(du -sh "$SCRIPT_DIR/Dictator.app" | cut -f1)
echo "✅ Distribution build complete!"
echo ""
echo "App location: $SCRIPT_DIR/Dictator.app"
echo "App size: $APP_SIZE"
echo ""
echo "To distribute:"
echo "  1. Zip the app: zip -r Dictator.zip Dictator.app install-dictator.sh INSTALL.txt"
echo "  2. Send Dictator.zip to your friends"
echo "  3. They run install-dictator.sh, then launch the app"
echo ""

if [ -d "$SCRIPT_DIR/Dictator.app/Contents/Resources/FluidAudio" ]; then
    echo "✓ Models bundled - app works offline!"
else
    echo "⚠️  Models NOT bundled - requires internet on first launch"
fi
