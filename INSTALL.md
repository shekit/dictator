# Installing Dictator

Thank you for trying Dictator! This guide will help you get started.

## System Requirements

- **macOS**: 14.0 (Sonoma) or later
- **Hardware**: Apple Silicon Mac (M1/M2/M3/M4)
- **Storage**: ~500MB free space

## Installation Steps

### From DMG (Recommended)

1. **Open** the DMG file (double-click)
2. **Drag** Dictator.app to the Applications folder
3. **Eject** the DMG
4. **Launch** Dictator from Applications

### From ZIP

1. **Unzip** the file
2. **Move** Dictator.app to your Applications folder
3. **Launch** from Applications

## First Launch - Security Warning

macOS will show a security warning because this app isn't from the App Store:

> "Dictator cannot be opened because it is from an unidentified developer"

### To Open Dictator:

**Method 1: Right-Click**
1. **Right-click** (or ⌃ Control-click) on Dictator.app
2. Select **"Open"**
3. Click **"Open"** in the dialog

**Method 2: System Settings**
1. Go to **System Settings > Privacy & Security**
2. Scroll to **Security** section
3. Click **"Open Anyway"** next to the Dictator message

⚠️ You only need to do this once!

## First Run - Onboarding

Dictator will guide you through setup:

### Step 1: Welcome
- Learn about the fn key shortcut

### Step 2: Accessibility Permission
- Click "Grant Permission"
- Toggle Dictator ON in System Settings
- Window automatically advances when granted

### Step 3: Microphone Permission
- Click "Grant Permission"
- Toggle Dictator ON in System Settings
- Window automatically advances when granted

### Step 4: API Key (Optional)
- Add your OpenRouter API key for AI cleanup
- Or skip to use raw transcription only

### Step 5: Done!
- You're ready to use Dictator

## Usage

### Basic Recording

1. **Hold** the fn key
2. **Speak** your message
3. **Release** the fn key
4. Text appears at your cursor!

### Menu Bar

Click the microphone icon in your menu bar to access:
- **Today's stats** (words, WPM)
- **Processing mode** (Cloud/Local/Off)
- **Model selection**
- **Settings window**
- **About**

### Settings Window

Press **⌘ ,** or select Settings from menu:

- **Prompts**: Customize AI cleanup instructions
- **Dictionary**: Add custom term replacements
- **History**: View past transcriptions
- **Stats**: See your usage statistics
- **Settings**: Configure API key, models, and startup

## Processing Modes

### Off (Raw Text) - Default
- No AI processing
- Fastest
- No API key needed
- Good for quick notes

### Cloud (OpenRouter)
- AI-powered cleanup
- Removes filler words (um, uh, like)
- Adds punctuation
- Requires API key ($0.001-0.01 per recording)

### Local (Ollama)
- AI-powered cleanup
- Fully offline
- Requires Ollama running locally
- Free

## Getting an OpenRouter API Key

1. Go to [openrouter.ai](https://openrouter.ai)
2. Sign up for an account
3. Add credits ($5 recommended for testing)
4. Create an API key
5. Copy key (starts with `sk-or-v1-`)
6. Paste into Dictator Settings

Cost: ~$0.001-0.01 per transcription (very cheap!)

## Using Ollama (Free Local AI)

1. Install Ollama from [ollama.ai](https://ollama.ai)
2. Open Terminal and run:
   ```bash
   ollama pull llama3.2:3b
   ollama serve
   ```
3. In Dictator, select **Local** mode
4. Choose your model

## Tips & Tricks

### Better Transcription
- Speak clearly and at normal pace
- Use in quiet environment
- Pause between sentences
- Hold fn key while speaking (don't release early)

### Better AI Cleanup
- Enable "Advanced Prompt" for correction handling
- Add custom dictionary entries for technical terms
- Try different models (Claude is great for quality, Llama is fast)

### Keyboard Shortcuts
- **fn (hold)**: Start/stop recording
- **fn + any key**: Cancel recording
- **⌘ ,**: Open Settings
- **⌘ Q**: Quit Dictator

## Troubleshooting

### "Nothing happens when I hold fn"
- Check menu bar icon shows "Ready"
- Verify Accessibility permission is granted
- Try restarting Dictator

### "No text appears after speaking"
- Check Microphone permission is granted
- Verify you're holding fn while speaking
- Look for error in menu bar

### "LLM processing not working"
- Verify API key is set correctly
- Check internet connection (Cloud mode)
- Verify Ollama is running (Local mode)
- Try switching to "Off" mode to test transcription

### "App won't open"
- Make sure you right-clicked and selected "Open"
- Check System Settings > Privacy & Security
- Try: `xattr -cr /Applications/Dictator.app` in Terminal

### "Poor transcription quality"
- First run downloads ASR models (~450MB) - wait for "ASR models ready" in Console
- Check microphone permissions
- Try speaking more clearly
- Use in quieter environment

## Storage Locations

Dictator stores files in these locations:

- **App**: `/Applications/Dictator.app`
- **Settings**: `~/Library/Preferences/com.dictator.app.plist`
- **ASR Models**: `~/Library/Application Support/FluidAudio/Models/` (~450MB)
- **Transcription Logs**: `~/Library/Application Support/Dictator/transcriptions.jsonl`

## Uninstalling

To completely remove Dictator:

1. Quit Dictator
2. Delete from Applications
3. Optionally remove data:
   ```bash
   rm -rf ~/Library/Application\ Support/Dictator/
   rm -rf ~/Library/Application\ Support/FluidAudio/
   rm ~/Library/Preferences/com.dictator.app.plist
   ```

## Privacy

- Voice processing happens **on-device** (local ASR)
- API key stored **locally** in UserDefaults
- Transcription logs stored **locally** on your Mac
- **No analytics** or telemetry
- Data only sent to OpenRouter/Ollama if you enable LLM mode

## Support

Having issues? Check Console.app for error messages (search for "Dictator").

## Enjoy!

Happy dictating! 🎤✨
