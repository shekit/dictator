#!/bin/bash

# Dictator - Development Environment Setup
# Run this at the start of each coding session

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/Dictator"

echo "=== Dictator Dev Environment Setup ==="
echo ""

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "ERROR: Xcode not found. Please install Xcode from the App Store."
    exit 1
fi
echo "✓ Xcode installed"

# Check Xcode command line tools
if ! xcode-select -p &> /dev/null; then
    echo "Installing Xcode command line tools..."
    xcode-select --install
fi
echo "✓ Xcode CLI tools installed"

# Check if project exists
if [ ! -d "$PROJECT_DIR" ]; then
    echo ""
    echo "Project directory not found at $PROJECT_DIR"
    echo "This is expected for Phase 1 - the project will be created."
    echo ""
else
    echo "✓ Project directory exists"

    # Resolve Swift packages if Package.swift exists
    if [ -f "$PROJECT_DIR/Package.swift" ]; then
        echo "Resolving Swift packages..."
        cd "$PROJECT_DIR"
        swift package resolve 2>/dev/null || true
        echo "✓ Swift packages resolved"
    fi
fi

# Check for Ollama (optional, for local LLM mode)
echo ""
echo "=== Optional Dependencies ==="

if command -v ollama &> /dev/null; then
    echo "✓ Ollama installed"
    if curl -s http://localhost:11434/api/tags &> /dev/null; then
        echo "✓ Ollama running"
        # List available models
        echo "  Available models:"
        curl -s http://localhost:11434/api/tags | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | head -5 | sed 's/^/    - /'
    else
        echo "⚠ Ollama installed but not running. Start with: ollama serve"
    fi
else
    echo "⚠ Ollama not installed (needed for local LLM mode)"
    echo "  Install with: brew install ollama"
fi

# Check for FluidAudio reference repo in sibling directory (for reference)
if [ -d "$SCRIPT_DIR/FluidAudio-main" ]; then
    echo "✓ FluidAudio reference available at ../FluidAudio-main"
fi

echo ""
echo "=== Environment Ready ==="
echo ""
echo "Next steps:"
echo "  1. Check features.json for next incomplete feature"
echo "  2. Check claude-progress.txt for recent progress"
echo ""

# Open project in Xcode if it exists
if [ -d "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/Package.swift" ]; then
    echo "Opening project in Xcode..."
    open "$PROJECT_DIR/Package.swift"
fi
