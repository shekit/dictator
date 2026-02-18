# Dictator - Architecture

## What It Does

Hold `fn` to record, speak, release, and Dictator inserts text at your cursor.

It supports:
- Push-to-talk: hold `fn`, release to finish
- Hands-free: press `fn + space` to start, press `space` to stop
- Optional LLM cleanup before insertion (Cloud/OpenRouter, Local/Ollama, or Off)

## Runtime Flow

```
fn/space hotkey
    -> AudioRecorder (AVAudioEngine, 16kHz mono conversion)
    -> Streaming STT (FluidAudio StreamingAsrManager)
    -> Final transcription on stop
    -> Optional LLM cleanup (OpenRouter or Ollama)
    -> TextInjectionService (PID unicode -> AX API -> clipboard fallback)
    -> Text appears in focused app
    -> Stats + JSONL history logged
```

## Core Components

### App lifecycle
- `AppDelegate` wires menu bar UI, onboarding, services, and shutdown.
- Services initialize after onboarding completes.

### Recording & hotkeys
- `GlobalHotkeyManager` uses CGEvent tap with health monitoring.
- `RecordingService` is the orchestration layer and state machine:
  - `idle`, `starting`, `recording`, `transcribing`, `processing`, `injecting`, `error`
- Handles race conditions during rapid key transitions.

### Speech-to-text (local)
- `TranscriptionService` uses FluidAudio and loads v2 Parakeet models.
- Streaming STT runs during recording; finalization happens on stop.
- Only one streaming session is active at a time; existing sessions are cancelled before a new one starts.

### LLM cleanup
- `LLMService` supports three modes:
  - `off` (raw text)
  - `local` (Ollama)
  - `cloud` (OpenRouter)
- Prompt construction has:
  - Main prompt
  - Optional advanced correction rules
  - Optional dictionary replacements

### Text injection
- `TextInjectionService` attempts insertion strategies in order:
  1. Unicode CGEvent to focused PID
  2. Accessibility text insertion
  3. Clipboard + Cmd+V fallback (with clipboard restore)

### UI
- Menu bar icon reflects runtime state.
- Menu includes today stats, LLM mode choices, conditional `Complete Setup...`, Settings, and Quit.
- Settings window tabs:
  - Prompts
  - Dictionary
  - History
  - Stats
  - Settings (API key, mode, models, launch at login)
- Floating recording indicator appears above dock during `starting/recording`.

## Onboarding

First run onboarding steps:
1. Welcome
2. Accessibility permission
3. Microphone permission
4. Optional OpenRouter API key
5. Model download progress
6. Done

Progress resumes if interrupted (`currentOnboardingStep`), and completion is tracked with `hasCompletedOnboarding`.

## Storage

| Data | Storage | Notes |
|------|---------|-------|
| API key + app settings | UserDefaults | API key key: `openRouterAPIKey` |
| Prompt/mode/model settings | UserDefaults | Managed by `LLMService` |
| Daily stats aggregates | UserDefaults | Key: `dictator.stats.daily` |
| Transcription history log | `~/Library/Application Support/Dictator/transcriptions.jsonl` | JSON Lines |
| ASR models | `~/Library/Application Support/FluidAudio/Models/` | Downloaded on first setup if not bundled |

## Dependencies

| Dependency | Purpose |
|------------|---------|
| FluidAudio | On-device ASR + streaming transcription |
| AppKit/SwiftUI/AVFoundation | Native macOS app, UI, audio capture |

## Error Handling

| Error | Behavior |
|-------|----------|
| Missing microphone permission | Prompt + user-facing error state |
| Missing accessibility permission | Prompt + open relevant settings pane |
| OpenRouter errors | Retry where applicable, then fallback to raw text |
| Ollama unavailable | Warn and offer to start server |
| Empty/too-short recording | Skip processing/injection safely |
| Disabled event tap | Auto re-enable via health checks |
