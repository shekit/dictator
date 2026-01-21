#!/bin/bash

# Reset Onboarding Script
# Completely resets Dictator app to first-run state

echo "🔄 Resetting Dictator app..."

# Kill the app if running
echo "  Killing Dictator app..."
killall Dictator 2>/dev/null || true

# Reset permissions
echo "  Resetting permissions..."
tccutil reset Microphone com.dictator.app 2>/dev/null || echo "    (Microphone permission not set)"
tccutil reset Accessibility com.dictator.app 2>/dev/null || echo "    (Accessibility permission not set)"

# Clear all UserDefaults
echo "  Clearing UserDefaults..."
defaults delete com.dictator.app 2>/dev/null || echo "    (No UserDefaults found)"

# Clear FluidAudio model cache (to simulate first-time download)
echo "  Clearing FluidAudio model cache..."
if [ -d ~/Library/Caches/com.fluidinference.fluidaudio ]; then
    rm -rf ~/Library/Caches/com.fluidinference.fluidaudio
    echo "    (Model cache removed - ~200MB will download on next launch)"
else
    echo "    (No model cache found)"
fi

# Optional: Clear transcription logs
# Uncomment if you want to clear logs too
# echo "  Clearing transcription logs..."
# rm -rf ~/Documents/Dictator/transcriptions.log 2>/dev/null || true

echo "✅ Reset complete! Launch Dictator to start fresh onboarding."
