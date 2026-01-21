#!/bin/bash
# Create macOS app icon (.icns) from a source image
# Usage: ./create-app-icon.sh <input-image.png>

set -e

if [ $# -eq 0 ]; then
    echo "Usage: ./create-app-icon.sh <input-image.png>"
    echo ""
    echo "Example: ./create-app-icon.sh icon-1024.png"
    echo ""
    echo "Requirements:"
    echo "  - Input image should be 1024x1024 PNG with transparent background"
    echo "  - Will create AppIcon.icns in the current directory"
    exit 1
fi

INPUT_IMAGE="$1"
ICONSET="AppIcon.iconset"
OUTPUT_ICON="AppIcon.icns"

if [ ! -f "$INPUT_IMAGE" ]; then
    echo "Error: Input file '$INPUT_IMAGE' not found"
    exit 1
fi

echo "🎨 Creating app icon from: $INPUT_IMAGE"
echo ""

# Create iconset directory
rm -rf "$ICONSET"
mkdir "$ICONSET"

# Generate all required icon sizes
echo "📐 Generating icon sizes..."
sips -z 16 16     "$INPUT_IMAGE" --out "$ICONSET/icon_16x16.png" > /dev/null
sips -z 32 32     "$INPUT_IMAGE" --out "$ICONSET/icon_16x16@2x.png" > /dev/null
sips -z 32 32     "$INPUT_IMAGE" --out "$ICONSET/icon_32x32.png" > /dev/null
sips -z 64 64     "$INPUT_IMAGE" --out "$ICONSET/icon_32x32@2x.png" > /dev/null
sips -z 128 128   "$INPUT_IMAGE" --out "$ICONSET/icon_128x128.png" > /dev/null
sips -z 256 256   "$INPUT_IMAGE" --out "$ICONSET/icon_128x128@2x.png" > /dev/null
sips -z 256 256   "$INPUT_IMAGE" --out "$ICONSET/icon_256x256.png" > /dev/null
sips -z 512 512   "$INPUT_IMAGE" --out "$ICONSET/icon_256x256@2x.png" > /dev/null
sips -z 512 512   "$INPUT_IMAGE" --out "$ICONSET/icon_512x512.png" > /dev/null
sips -z 1024 1024 "$INPUT_IMAGE" --out "$ICONSET/icon_512x512@2x.png" > /dev/null

echo "✅ Generated all icon sizes"
echo ""

# Convert to .icns
echo "🔧 Converting to .icns format..."
iconutil -c icns "$ICONSET" -o "$OUTPUT_ICON"

# Clean up
rm -rf "$ICONSET"

echo "✅ Icon created: $OUTPUT_ICON"
echo ""
echo "Next steps:"
echo "  1. Move AppIcon.icns to Dictator/Sources/Dictator/Resources/"
echo "  2. Update Info.plist to reference the icon"
echo "  3. Rebuild the app"
echo ""
