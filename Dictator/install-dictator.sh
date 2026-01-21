#!/bin/bash
# Dictator Installation Script
# This script removes macOS quarantine attributes to allow the app to run

set -e

echo "🎙️  Installing Dictator..."
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$SCRIPT_DIR/Dictator.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: Dictator.app not found in the same directory as this script"
    exit 1
fi

echo "📦 Removing quarantine attributes..."
xattr -cr "$APP_PATH"

echo "✅ Installation complete!"
echo ""
echo "You can now open Dictator by:"
echo "  1. Double-clicking Dictator.app"
echo "  2. Or running: open \"$APP_PATH\""
echo ""
echo "Note: On first launch, macOS will ask for Microphone and Accessibility permissions."
echo ""
