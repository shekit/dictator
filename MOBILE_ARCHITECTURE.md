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

Two buttons. That's it.

```
┌─────────────────────────────────────────┐
│                                         │
│            ┌───────────┐                │
│            │           │                │
│            │    🎤     │                │
│            │           │                │
│            └───────────┘                │
│                                         │
│  [🌐]                                   │
└─────────────────────────────────────────┘
```

During recording:

```
┌─────────────────────────────────────────┐
│                                         │
│            ┌───────────┐                │
│            │    ⏹️     │                │
│            │  ●  REC   │                │
│            └───────────┘                │
│                                         │
│  [🌐]    "Hello world..."              │
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
│  │  - All settings (cloud LLM, API    │  │
│  │    key, model selection)           │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
                    │
                    │ SharedPreferences
                    ▼
┌──────────────────────────────────────────┐
│      Input Method Service (IME)          │
│  ┌────────────────────────────────────┐  │
│  │  - Mic button + globe button only  │  │
│  │  - STT (SpeechRecognizer → later   │  │
│  │    swap to Whisper.cpp)            │  │
│  │  - Text insertion via              │  │
│  │    InputConnection                 │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

**Key Android Components:**
- `InputMethodService` subclass for the keyboard
- Android `SpeechRecognizer` for STT (Phase 15), with Whisper.cpp as an alternative (Phase 18). User chooses STT engine in settings.
- Keyboard has only two buttons: mic and globe (all settings live in the main app)
- SharedPreferences for sharing settings between app and IME
- No special permissions beyond RECORD_AUDIO

## Speech-to-Text Options

| Platform | Option | Pros | Cons |
|----------|--------|------|------|
| **iOS** | SFSpeechRecognizer | Built-in, no extra dependencies | Requires network for best quality |
| **iOS** | Whisper.cpp | Fully offline, high quality | Adds ~50-150MB, more complex |
| **Android** | Whisper.cpp | Fully offline, high quality | Requires JNI wrapper, ~50-150MB |
| **Android** | Vosk | Offline, lightweight | Lower accuracy than Whisper |
| **Android** | Google Speech API | High quality | Requires network, API costs |

**Android strategy:** Start with Android's built-in `SpeechRecognizer` (zero setup, instant results). Swap to Whisper.cpp in Phase 18 for fully offline STT.

**iOS strategy:** Start with `SFSpeechRecognizer` for simplicity.

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

## Android Phases

See `features.json` for full feature list and verification steps.

| Phase | Name | What |
|-------|------|------|
| 14 | Keyboard Shell | IME with mic + globe buttons |
| 15 | Dictation | SpeechRecognizer → InputConnection |
| 16 | Whisper Option | Add Whisper.cpp as alternative STT engine (user toggle) |
| 17 | Polish | Haptics, auto-stop, live preview, errors |
| 18 | Main App | Onboarding, settings, SharedPreferences |
| 19 | Stats & Transcriptions | WPM tracking, session history, Room database |
| 20 | Cloud LLM | OpenRouter integration for text cleanup |

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
android/
├── app/
│   ├── src/main/
│   │   ├── java/.../
│   │   │   ├── MainActivity.kt
│   │   │   ├── SettingsActivity.kt
│   │   │   ├── DictatorIME.kt          # InputMethodService
│   │   │   ├── KeyboardView.kt
│   │   │   ├── AudioRecorder.kt
│   │   │   └── SpeechRecognizer.kt
│   │   │
│   │   └── res/
│   │       └── xml/
│   │           └── method.xml          # IME configuration
│   │
│   └── build.gradle.kts
├── build.gradle.kts
├── settings.gradle.kts
└── gradle/
```

## What's Different from macOS Version

| Aspect | macOS | Mobile |
|--------|-------|--------|
| Trigger | Global hotkey (Ctrl+Option+Space) | Tap mic button on keyboard |
| Text injection | Clipboard + Cmd+V simulation | Keyboard types directly |
| Local LLM | Ollama server | Not supported (cloud only) |
| UI | Menu bar + settings window | Keyboard + main app |
| Always available | Yes (global hotkey) | Only when keyboard is active |

## Resolved Decisions

- **Auto-stop on silence:** Yes, Phase 17
- **Live preview:** Yes, Phase 17
- **Haptic feedback:** Yes, Phase 17
- **Keyboard UI:** Minimal — mic button + globe only, all settings in main app
