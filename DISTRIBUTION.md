# Dictator - Distribution Guide

This guide explains how to package and distribute Dictator to your friends.

## Quick Start

Run the packaging script:

```bash
cd Dictator
./package-for-distribution.sh
```

This creates two files in the `dist/` folder:
- **Dictator-v1.0.0.dmg** - Drag-and-drop installer (recommended)
- **Dictator-v1.0.0.zip** - Direct app bundle archive

## Distribution Options

### Option 1: DMG File (Recommended)

The DMG provides a nice installation experience:
1. Double-click to open
2. Drag Dictator to Applications folder
3. Eject the DMG

Share the DMG file via:
- Email (if under 25MB)
- Cloud storage (Dropbox, Google Drive, iCloud)
- File sharing services (WeTransfer, Send)
- GitHub Releases

### Option 2: ZIP File

Alternative for simpler distribution:
1. Unzip the file
2. Move Dictator.app to Applications
3. Launch from Applications

## Important: First Launch

Your friends will see a security warning because the app isn't signed with an Apple Developer certificate:

**"Dictator cannot be opened because it is from an unidentified developer"**

### How to Open:

1. **Right-click** (or Control-click) on Dictator.app
2. Select **"Open"** from the menu
3. Click **"Open"** in the security dialog
4. This only needs to be done once

Alternatively, they can:
1. Go to **System Settings > Privacy & Security**
2. Scroll to the Security section
3. Click **"Open Anyway"** next to the Dictator message

## System Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (M1/M2/M3)
- Approximately 500MB free disk space (for ASR models)

## Optional: Code Signing

If you want to avoid the security warning, you can sign the app with an Apple Developer certificate:

### Step 1: Get a Developer Certificate

1. Enroll in [Apple Developer Program](https://developer.apple.com/programs/) ($99/year)
2. Create a **Developer ID Application** certificate in Xcode
3. Install the certificate on your Mac

### Step 2: Sign the App

Edit `package-for-distribution.sh` and uncomment these lines:

```bash
echo "🔐 Code signing..."
codesign --force --deep --sign "Developer ID Application: Your Name" "$APP_BUNDLE"
echo "✅ App signed"
```

Replace `"Your Name"` with your certificate name from Keychain Access.

### Step 3: Notarize (Optional)

For macOS 10.15+ without warnings:

```bash
# Create app-specific password at appleid.apple.com
xcrun notarytool submit dist/Dictator-v1.0.0.zip \
  --apple-id your@email.com \
  --password "xxxx-xxxx-xxxx-xxxx" \
  --team-id XXXXXXXXXX \
  --wait

# Staple the notarization ticket
xcrun stapler staple Dictator.app
```

## Distribution Checklist

Before sharing:

- [ ] Test the app on a clean Mac (or create a new user account)
- [ ] Verify onboarding flow works correctly
- [ ] Check that permissions are requested properly
- [ ] Include installation instructions
- [ ] Warn about first-launch security dialog

## File Sizes

Typical distribution sizes:
- App bundle: ~10-15MB
- ZIP file: ~8-12MB
- DMG file: ~10-14MB

After installation:
- App: ~10-15MB
- ASR models (first run): ~450MB in `~/Library/Application Support/FluidAudio/`
- Logs: ~1-5MB in `~/Library/Application Support/Dictator/`

## Support & Updates

When distributing updates:

1. Increment version in the script (`VERSION="1.0.1"`)
2. Rebuild and redistribute
3. Users should quit the old version before installing new one
4. Settings and history are preserved (stored in UserDefaults)

## Privacy & Data

Inform your friends:
- All voice processing happens locally (on-device ASR)
- API key is stored locally in UserDefaults
- Transcription logs are stored locally in Application Support
- No data is sent anywhere except OpenRouter/Ollama if LLM mode is enabled
- No analytics or telemetry

## Troubleshooting

### "App is damaged and can't be opened"

This happens if the app was quarantined by macOS. Fix:

```bash
xattr -cr /Applications/Dictator.app
```

### Permissions not working

Reset permissions:

```bash
tccutil reset Microphone com.dictator.app
tccutil reset Accessibility com.dictator.app
```

### App won't launch

Check Console.app for error messages, look for "Dictator" in the log.

## Alternative: TestFlight (Beta Testing)

For easier distribution without code signing warnings:

1. Upload to App Store Connect
2. Add friends as beta testers
3. They install via TestFlight app
4. No security warnings, automatic updates

Note: Requires Apple Developer Program membership.

## Questions?

For issues or questions about distribution, check:
- [Apple's Gatekeeper documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Swift Package Manager docs](https://swift.org/package-manager/)
