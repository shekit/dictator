# Dictator - Architecture

## What It Does

Hold a hotkey → speak → release → cleaned text appears at your cursor.

## Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   Hold Hotkey ──→ Record Audio ──→ Release ──→ FluidAudio STT          │
│                                                     │                   │
│                                                     ▼                   │
│                                              Raw Transcription          │
│                                                     │                   │
│                                         [LLM Cleanup Enabled?]          │
│                                           /              \              │
│                                         NO               YES            │
│                                          │                │             │
│                                          │    ┌──────────┴──────────┐  │
│                                          │    │                     │  │
│                                          │  [Local]             [Cloud] │
│                                          │    │                     │  │
│                                          │    ▼                     ▼  │
│                                          │  Ollama            OpenRouter│
│                                          │    │                     │  │
│                                          │    └──────────┬──────────┘  │
│                                          │               │              │
│                                          │               ▼              │
│                                          │        Cleaned Text          │
│                                          │               │              │
│                                          └───────┬───────┘              │
│                                                  │                      │
│                                                  ▼                      │
│                                      Clipboard + Cmd+V Paste            │
│                                                  │                      │
│                                                  ▼                      │
│                                           Text at Cursor                │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Menu Bar App
- Lives in system tray
- Shows recording state
- Quick toggle: Local ↔ Cloud mode
- Stats: words today, WPM
- Opens settings window

### 2. Audio Recording
- Global hotkey: hold-to-record (Ctrl+Option+Space)
- AVAudioEngine for capture
- Microphone permission handling

### 3. Speech-to-Text
- FluidAudio with Parakeet model
- Runs on Apple Neural Engine
- ~200ms latency, fully local

### 4. LLM Text Processing

**Three-section prompt system:**

| Section | Purpose | Example |
|---------|---------|---------|
| Main | Filler removal, punctuation | "um hello" → "Hello." |
| Advanced | Backtrack handling | "wait no actually hi" → "Hi." |
| Dictionary | Custom terms | "ant row pic" → "Anthropic" |

**Two modes:**
- **Local:** Ollama (fully offline)
- **Cloud:** OpenRouter → Groq/Claude/GPT

### 5. Text Injection
- Clipboard + Cmd+V simulation
- Works in any app
- Preserves original clipboard

### 6. Stats & Logging
- Word count per transcription
- WPM (words per minute)
- Daily aggregates
- Transcription log file with timestamps

## Data Storage

| Data | Location | Format |
|------|----------|--------|
| API Keys & Config | .env (project root) | KEY=value |
| Settings | UserDefaults | Plist |
| Stats | ~/Library/Application Support/Dictator/stats.json | JSON |
| Transcription Log | ~/Documents/Dictator/transcriptions.jsonl | JSON Lines |
| Prompts | UserDefaults | String |

## Dependencies

| Dependency | Purpose |
|------------|---------|
| FluidAudio | Speech-to-text (Parakeet on ANE) |
| None else | Pure Swift/AppKit/SwiftUI |

## UI Structure

```
Menu Bar
├── Icon (changes during recording)
├── Mode Toggle [Local ▼] / [Cloud ▼]
├── LLM Cleanup [✓ On / Off]
├── Stats: "Today: 1,234 words | 142 WPM"
├── ───────────
├── Settings... → Opens Settings Window
└── Quit

Settings Window
├── [Prompts] Tab
│   ├── Main Prompt (text area)
│   ├── Advanced Prompt (text area + toggle)
│   └── Dictionary (text area)
├── [History] Tab
│   └── List of past transcriptions
├── [Settings] Tab
│   ├── Hotkey configuration
│   ├── API Key status (loaded from .env)
│   ├── Local model picker
│   ├── Cloud model picker
│   └── Launch at login toggle
└── [Stats] Tab
    └── Daily/weekly/all-time stats
```

## Error Handling

| Error | Handling |
|-------|----------|
| Ollama not running | Show warning, suggest starting Ollama |
| OpenRouter API error | Show error, fall back gracefully |
| No microphone permission | Prompt for permission |
| Empty recording | Ignore, don't process |
| FluidAudio model missing | Download on first run |
