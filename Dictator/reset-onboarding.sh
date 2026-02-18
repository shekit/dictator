#!/bin/bash

# Reset Onboarding Script
# Completely resets Dictator app to first-run state
#
# Usage:
#   ./reset-onboarding.sh              # Reset without deleting models
#   ./reset-onboarding.sh --clear-models   # Reset and delete models (~443MB re-download)

# Parse arguments
CLEAR_MODELS=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --clear-models|-m)
            CLEAR_MODELS=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: ./reset-onboarding.sh [--clear-models]"
            exit 1
            ;;
    esac
done

echo "🔄 Resetting Dictator app..."

# Kill the app if running
echo "  Killing Dictator app..."
killall Dictator 2>/dev/null || true

# Reset permissions
echo "  Resetting permissions..."
tccutil reset Microphone it.shek.dictator 2>/dev/null || echo "    (Microphone permission not set)"
tccutil reset Accessibility it.shek.dictator 2>/dev/null || echo "    (Accessibility permission not set)"

# Clear all UserDefaults
echo "  Clearing UserDefaults..."
defaults delete it.shek.dictator 2>/dev/null || echo "    (No UserDefaults found)"

# Conditionally clear FluidAudio models
if [ "$CLEAR_MODELS" = true ]; then
    echo "  Clearing FluidAudio models (--clear-models flag set)..."
    MODELS_DIR="$HOME/Library/Application Support/FluidAudio"
    if [ -d "$MODELS_DIR" ]; then
        MODEL_SIZE=$(du -sh "$MODELS_DIR" 2>/dev/null | cut -f1)
        rm -rf "$MODELS_DIR"
        echo "    ✓ Models removed (~$MODEL_SIZE will re-download on next launch)"
    else
        echo "    (No models found)"
    fi
else
    echo "  Keeping FluidAudio models (use --clear-models to delete)"
    MODELS_DIR="$HOME/Library/Application Support/FluidAudio/Models"
    if [ -d "$MODELS_DIR" ]; then
        MODEL_SIZE=$(du -sh "$MODELS_DIR" 2>/dev/null | cut -f1)
        echo "    (Models present: ~$MODEL_SIZE)"
    fi
fi

echo "✅ Reset complete! Launch Dictator to start fresh onboarding."
