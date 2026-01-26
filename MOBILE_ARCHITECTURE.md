# Dictator Mobile - Architecture

## What We're Building

A minimal dictation keyboard for iOS and Android. Users switch to this keyboard when they want to dictate, speak, and the text is inserted into whatever app they're using. Then they switch back to their regular keyboard (SwiftKey, Gboard, etc.) for normal typing.

## Core Flow

```
User in any app (WhatsApp, Notes, etc.)
         │
         ▼
Switch to Dictator keyboard (globe icon)
         │
         ▼
    Tap mic button
         │
         ▼
    Speak naturally
         │
         ▼
  Tap stop (or auto-stop on silence)
         │
         ▼
   On-device STT converts speech → text
         │
         ▼
  [Optional] Cloud LLM cleans up text
         │
         ▼
   Text inserted into active field
         │
         ▼
Switch back to regular keyboard
```

## Keyboard UI

Intentionally minimal - this is not a general-purpose keyboard:

```
┌─────────────────────────────────────────┐
│                                         │
│            ┌───────────┐                │
│            │           │                │
│            │    🎤     │   Tap to       │
│            │           │   Dictate      │
│            └───────────┘                │
│                                         │
│  [🌐 Switch Keyboard]    [⚙️ Settings]  │
│                                         │
└─────────────────────────────────────────┘
```

During recording:

```
┌─────────────────────────────────────────┐
│                                         │
│            ┌───────────┐                │
│            │    ⏹️     │   Tap to       │
│            │  ●  REC   │   Stop         │
│            └───────────┘                │
│                                         │
│         "Hello world..."                │
│         (live preview)                  │
│                                         │
└─────────────────────────────────────────┘
```

## Platform Architecture

### iOS

```
┌──────────────────────────────────────────┐
│              Main App                    │
│  ┌────────────────────────────────────┐  │
│  │  - Onboarding & permissions        │  │
│  │  - Settings (cloud LLM toggle)     │  │
│  │  - API key configuration           │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
                    │
                    │ App Groups (shared data)
                    ▼
┌──────────────────────────────────────────┐
│         Keyboard Extension               │
│  ┌────────────────────────────────────┐  │
│  │  - Mic button UI                   │  │
│  │  - Audio recording (AVAudioEngine) │  │
│  │  - STT (SFSpeechRecognizer)        │  │
│  │  - Text insertion                  │  │
│  │  - Cloud LLM client (optional)     │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

**Key iOS Components:**
- `UIInputViewController` subclass for the keyboard
- `SFSpeechRecognizer` for on-device STT
- App Groups for sharing settings between app and keyboard
- "Allow Full Access" required only if using cloud LLM

### Android

```
┌──────────────────────────────────────────┐
│              Main App                    │
│  ┌────────────────────────────────────┐  │
│  │  - Onboarding & permissions        │  │
│  │  - Settings (cloud LLM toggle)     │  │
│  │  - API key configuration           │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
                    │
                    │ SharedPreferences
                    ▼
┌──────────────────────────────────────────┐
│      Input Method Service (IME)          │
│  ┌────────────────────────────────────┐  │
│  │  - Mic button UI (Compose)         │  │
│  │  - Audio recording (AudioRecord)   │  │
│  │  - STT (Whisper.cpp or Vosk)       │  │
│  │  - Text insertion                  │  │
│  │  - Cloud LLM client (optional)     │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

**Key Android Components:**
- `InputMethodService` subclass for the keyboard
- Whisper.cpp (via JNI) or Vosk for on-device STT
- SharedPreferences for settings
- No special permissions beyond microphone

## Speech-to-Text Options

| Platform | Option | Pros | Cons |
|----------|--------|------|------|
| **iOS** | SFSpeechRecognizer | Built-in, no extra dependencies | Requires network for best quality |
| **iOS** | Whisper.cpp | Fully offline, high quality | Adds ~50-150MB, more complex |
| **Android** | Whisper.cpp | Fully offline, high quality | Requires JNI wrapper, ~50-150MB |
| **Android** | Vosk | Offline, lightweight | Lower accuracy than Whisper |
| **Android** | Google Speech API | High quality | Requires network, API costs |

**Recommendation:** Start with platform-native (SFSpeechRecognizer on iOS) for simplicity, evaluate Whisper.cpp later if offline quality matters.

## Cloud LLM Integration (Optional)

Same as macOS version - OpenRouter API for text cleanup:

```
Raw transcription: "um so like I was thinking we should uh meet tomorrow"
                                    │
                                    ▼
                            OpenRouter API
                                    │
                                    ▼
Cleaned text: "I was thinking we should meet tomorrow."
```

- Disabled by default (works fully offline)
- User enables in settings and provides API key
- iOS: Requires "Allow Full Access" permission for network

## Permissions Required

### iOS
| Permission | When | Why |
|------------|------|-----|
| Microphone | First dictation | Audio recording |
| Speech Recognition | First dictation | On-device STT |
| Full Access (optional) | If cloud LLM enabled | Network for API calls |

### Android
| Permission | When | Why |
|------------|------|-----|
| RECORD_AUDIO | First dictation | Audio recording |
| INTERNET (optional) | If cloud LLM enabled | Network for API calls |

## Data Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Record    │────▶│     STT     │────▶│   Insert    │
│   Audio     │     │  (on-device)│     │    Text     │
└─────────────┘     └─────────────┘     └─────────────┘
                           │
                           ▼ (optional)
                    ┌─────────────┐
                    │  Cloud LLM  │
                    │   Cleanup   │
                    └─────────────┘
```

No audio or text leaves the device unless cloud LLM is explicitly enabled.

## Phased Implementation

### Phase 1: Minimal Keyboard (MVP)
- Keyboard with mic button
- On-device STT
- Text insertion
- Switch keyboard button
- **Goal:** Dictate text into any app

### Phase 2: Polish
- Live transcription preview while speaking
- Auto-stop on silence detection
- Recording indicator animation
- Error handling (no mic permission, etc.)

### Phase 3: Cloud LLM
- Settings screen in main app
- API key configuration
- Toggle for cloud cleanup
- OpenRouter integration

### Phase 4: Enhancements
- Custom dictionary (proper nouns)
- Punctuation commands ("period", "comma")
- Multiple languages
- Haptic feedback

## File Structure

### iOS
```
DictatorMobile/
├── DictatorApp/           # Main app target
│   ├── App.swift
│   ├── OnboardingView.swift
│   ├── SettingsView.swift
│   └── Shared/
│       ├── Settings.swift
│       └── LLMClient.swift
│
├── DictatorKeyboard/      # Keyboard extension target
│   ├── KeyboardViewController.swift
│   ├── KeyboardView.swift
│   ├── AudioRecorder.swift
│   └── SpeechRecognizer.swift
│
└── Shared/                # App Group shared code
    └── UserSettings.swift
```

### Android
```
app/
├── src/main/
│   ├── java/.../
│   │   ├── MainActivity.kt
│   │   ├── SettingsActivity.kt
│   │   ├── DictatorIME.kt          # InputMethodService
│   │   ├── KeyboardView.kt
│   │   ├── AudioRecorder.kt
│   │   └── SpeechRecognizer.kt
│   │
│   └── res/
│       └── xml/
│           └── method.xml          # IME configuration
│
└── whisper/                        # Whisper.cpp module (if used)
```

## What's Different from macOS Version

| Aspect | macOS | Mobile |
|--------|-------|--------|
| Trigger | Global hotkey (Ctrl+Option+Space) | Tap mic button on keyboard |
| Text injection | Clipboard + Cmd+V simulation | Keyboard types directly |
| Local LLM | Ollama server | Not supported (cloud only) |
| UI | Menu bar + settings window | Keyboard + main app |
| Always available | Yes (global hotkey) | Only when keyboard is active |

## Open Questions

1. **Auto-stop on silence?** Should recording automatically stop after N seconds of silence, or require explicit tap to stop?

2. **Live preview?** Show transcription as user speaks, or only after they stop?

3. **Haptic feedback?** Vibrate on start/stop recording?

4. **Keyboard height?** Match system keyboard height or use minimal height?

5. **iOS "Allow Full Access" messaging?** How to explain the scary warning if user wants cloud LLM?
