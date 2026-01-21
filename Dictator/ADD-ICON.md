# Adding an App Icon

Your app is configured to use a custom icon. Follow these steps to add one:

## Option 1: Quick Start (Use Existing Image)

If you have a PNG image (preferably 1024x1024):

```bash
cd /Users/abhishek/Documents/bigmac/dictator/Dictator
./create-app-icon.sh your-icon.png
mv AppIcon.icns Sources/Dictator/Resources/
```

Done! Rebuild the app and it will have your icon.

## Option 2: Design Your Own Icon

### Using SF Symbols (Mac Built-in)

1. Open **SF Symbols** app (comes with Xcode)
2. Find a microphone symbol (search "mic")
3. Export as PNG at 1024x1024
4. Use the script above to convert it

### Using Design Software

**Figma/Sketch/Photoshop:**
1. Create a 1024x1024 canvas
2. Design your icon (keep it simple!)
3. Export as PNG with transparent background
4. Use the script to convert

**Icon Design Tips:**
- Use a microphone or waveform symbol
- Keep it simple and recognizable
- Use blue/purple colors (matches the app theme)
- Make it work at small sizes (16x16)
- Transparent or solid background both work

## Option 3: Use an AI Generator

**Prompt for ChatGPT/Midjourney:**
> "A minimalist app icon for a voice dictation app, featuring a microphone symbol, blue and purple gradient, modern flat design, 1024x1024"

Then download and use the script to convert.

## Option 4: Use Online Tools

**Free Icon Generators:**
1. [Canva](https://canva.com) - Free templates
2. [Figma](https://figma.com) - Free design tool
3. [IconKitchen](https://icon.kitchen) - App icon generator

**Convert Image to .icns:**
- Our script does this automatically
- Or use [CloudConvert](https://cloudconvert.com) to convert PNG → ICNS

## What the Icon Should Look Like

Good icon ideas for Dictator:
- 🎤 Microphone icon (simple, clean)
- 🌊 Waveform/audio wave
- 💬 Speech bubble
- Combination of mic + waveform
- Letters "D" or "DC" stylized

**Colors that match the app:**
- Primary: Blue (#007AFF)
- Accent: Purple/Violet
- Background: White or gradient

## File Requirements

- **Format:** .icns (use the script to create this)
- **Location:** `Dictator/Sources/Dictator/Resources/AppIcon.icns`
- **Name:** Must be exactly `AppIcon.icns`
- **Source:** 1024x1024 PNG recommended

## Testing Your Icon

After adding the icon:

```bash
./build-app.sh
open Dictator.app
```

You should see your icon in:
- Finder
- Applications folder
- Dock (if you pin it)
- Menu bar (uses SF Symbol, not this icon)

## Example: Creating a Simple Icon

**Super simple approach using ImageMagick:**

```bash
# Install ImageMagick if needed
brew install imagemagick

# Create a simple blue circle icon
convert -size 1024x1024 xc:none \
  -fill "#007AFF" -draw "circle 512,512 512,100" \
  -font "Helvetica-Bold" -pointsize 400 -fill white \
  -gravity center -annotate +0+0 "D" \
  icon.png

# Convert to .icns
./create-app-icon.sh icon.png
mv AppIcon.icns Sources/Dictator/Resources/
```

## Troubleshooting

**Icon not showing up:**
- Make sure file is named exactly `AppIcon.icns`
- Check it's in `Sources/Dictator/Resources/`
- Rebuild the app completely
- Try deleting the old .app and rebuilding

**Icon looks blurry:**
- Start with a larger source image (1024x1024 minimum)
- Export as PNG, not JPG
- Don't use gradients that are too subtle

**Wrong icon showing:**
- macOS caches icons - restart Finder or log out/in
- Delete the .app bundle and rebuild
- Clear icon cache: `sudo find /private/var/folders/ -name com.apple.dock.iconcache -exec rm {} \;`

## Skip the Icon (Optional)

If you don't want a custom icon, the app will use a default generic icon. Everything still works fine!

Just delete these lines from `Info.plist`:
```xml
<key>CFBundleIconFile</key>
<string>AppIcon</string>
```
