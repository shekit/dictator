#!/bin/bash
# Bundle FluidAudio models with the app for distribution
# This downloads the models and includes them in the app bundle

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$SCRIPT_DIR/Dictator.app"

echo "📦 Bundling FluidAudio models with app..."
echo ""

# Check if app bundle exists
if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ Error: Dictator.app not found. Run ./build-app.sh first."
    exit 1
fi

# FluidAudio models cache location
MODELS_CACHE="$HOME/Library/Caches/com.fluidinference.fluidaudio/models/v2"
APP_MODELS_DIR="$APP_BUNDLE/Contents/Resources/FluidAudio/models/v2"

# Check if models exist locally
if [ ! -d "$MODELS_CACHE" ]; then
    echo "⚠️  FluidAudio models not found in cache."
    echo "To download models:"
    echo "  1. Launch Dictator.app once"
    echo "  2. Complete onboarding (models download in background)"
    echo "  3. Run this script again"
    echo ""
    echo "Or download manually from: https://github.com/FluidInference/FluidAudio/releases"
    exit 1
fi

echo "✓ Found models in cache: $MODELS_CACHE"

# Create models directory in app bundle
mkdir -p "$APP_MODELS_DIR"

# Copy models to app bundle
echo "Copying models to app bundle..."
cp -R "$MODELS_CACHE"/* "$APP_MODELS_DIR/"

# Get model size
MODEL_SIZE=$(du -sh "$APP_MODELS_DIR" | cut -f1)
echo "✓ Models bundled ($MODEL_SIZE)"

echo ""
echo "✅ Models successfully bundled!"
echo "The app will now work offline without downloading models."
echo ""
echo "Note: App bundle size increased by ~$MODEL_SIZE"
