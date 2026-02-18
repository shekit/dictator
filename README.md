# Dictator

Free, local and private dictation app for macOS. Go from 40 WPM typing to 150+.

Hold `fn`, speak, release - text appears at your cursor. 

Optionally enable AI post-processing to strip filler words, fix spelling, and add punctuation.

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon Mac (M1/M2/M3/M4)
- ~500MB free space (for speech models)

## Install from DMG (Easy)

1. Download the latest `.dmg` from [Releases](https://github.com/shekit/dictator/releases)
2. Drag `Dictator.app` to `/Applications`
3. Launch Dictator

**If macOS blocks the app on first launch:**

Right-click it, choose **Open**, then click **Open** in the dialog (one-time only). The app walks you through permissions and model setup.

## Build from source

```bash
git clone git@github.com:shekit/dictator.git
cd dictator
./init.sh
cd Dictator
./build-app.sh
open Dictator.app
```

Requires Xcode Command Line Tools and Swift 5.9+.

## Usage

| Action | What happens |
|--------|-------------|
| **Hold fn** | Start recording |
| **Release fn** | Stop recording, process, insert text |
| **fn + other key** | Cancel recording |
| **fn + space** | Start hands-free recording |
| **space** | Stop hands-free recording |

Click the menu bar icon to see today's word count and WPM, switch processing mode, or open Settings

## Processing modes

| Mode | Description |
|------|-------------|
| **Off** | Raw transcription, no cleanup. Fastest, no API key needed. |
| **Cloud** | AI cleanup via [OpenRouter](https://openrouter.ai). Requires API key (~$0.001/use). |
| **Local** | AI cleanup via [Ollama](https://ollama.ai) running locally. Free, fully offline. |

Configure your API key or Ollama connection from the Settings window.

## Troubleshooting

- **Nothing happens when holding fn** — Check the menu bar icon is visible and Accessibility permission is granted.
- **No text after speaking** — Verify Microphone permission is granted.
- **LLM cleanup not working** — Check API key (Cloud) or that Ollama is running (Local). Switch to Off to test transcription alone.
- **"App is damaged"** — Run `xattr -cr /Applications/Dictator.app` in Terminal.

## Privacy

All voice processing happens on-device. No analytics or telemetry. Data is only sent to OpenRouter if you enable Cloud mode. Local mode (Ollama) stays entirely on your machine. Transcription logs are stored locally at `~/Library/Application Support/Dictator/transcriptions.jsonl`.

## More docs

- [DISTRIBUTION.md](DISTRIBUTION.md) — Packaging, signing, notarization
- [ARCHITECTURE.md](ARCHITECTURE.md) — Runtime architecture

## License

MIT License. See [LICENSE](LICENSE).
