# Dictator - Agent Instructions

## Project Overview

Dictator is a macOS menu bar app for voice-to-text dictation with LLM-powered text cleanup. Hold a hotkey, speak, release, and cleaned text appears at your cursor.

## Tech Stack

- **Language:** Swift 5.9+
- **Platform:** macOS 14.0+ (Sonoma), Apple Silicon
- **STT:** FluidAudio (Parakeet model on Neural Engine)
- **LLM Local:** Ollama (localhost:11434)
- **LLM Cloud:** OpenRouter API (Groq, Claude, etc.)
- **UI:** SwiftUI + AppKit (menu bar + settings window)

## Session Protocol

Every coding session, follow this sequence:

1. **Orient:** Read `claude-progress.txt` and recent git commits
2. **Select:** Find the next `"passes": false` feature in `features.json`
3. **Setup:** Run `./init.sh` if needed
4. **Implement:** Work on ONE feature at a time
5. **Test:** Verify using the feature's verification steps
6. **Commit:** Make a descriptive git commit
7. **Update:** Mark feature as `"passes": true` in `features.json`
8. **Log:** Append progress to `claude-progress.txt`

## Rules

### Do
- Work on features in phase order (Phase 1 before Phase 2, etc.)
- Test each feature before marking it complete
- Make atomic commits (one feature = one commit)
- Leave code in a compilable state at session end
- Update progress files before ending session

### Don't
- Skip phases or work out of order
- Mark features as passing without verification
- Remove or modify feature descriptions in `features.json` (only modify `passes` field)
- Leave uncommitted changes at session end
- Work on multiple features simultaneously

## File Structure

```
dictator/
├── CLAUDE.md                 # This file - agent instructions
├── ARCHITECTURE.md           # Project architecture overview
├── features.json             # Feature tracking (update passes field only)
├── claude-progress.txt       # Session progress log (append only)
├── init.sh                   # Dev environment setup script
└── Dictator/                 # Main Xcode project (to be created)
    ├── Package.swift
    └── Sources/
        └── Dictator/
            ├── App/          # App entry point, AppDelegate
            ├── Audio/        # Recording, microphone capture
            ├── STT/          # FluidAudio integration
            ├── LLM/          # Ollama + OpenRouter clients
            ├── Injection/    # Clipboard, text injection
            ├── UI/           # Menu bar, settings window
            ├── Stats/        # Word count, WPM, logging
            └── Storage/      # Persistence, settings
```

## Reference Implementations

If stuck on implementation patterns, consult these sibling folders:

| Folder | Use For |
|--------|---------|
| `../FluidAudio-main` | STT library - this is our dependency |
| `../FluidVoice-main` | **Best reference** - production macOS app using FluidAudio + LLM cleanup |
| `../starling-main` | Simple Swift menu bar app, text injection patterns |
| `../tambourine-voice-main` | 3-section prompt system, Ollama/OpenRouter integration |

## Environment Variables

All API keys and configuration are stored in `.env` file (never commit this file).

```bash
# .env
OPENROUTER_API_KEY=sk-or-...      # Required for cloud mode
OLLAMA_HOST=http://localhost:11434 # Optional, defaults to localhost:11434
```

Load these in the app at startup. See `.env.example` for template.

## Key Implementation Notes

### FluidAudio Integration
```swift
import FluidAudio

let asrManager = AsrManager()
let transcription = try await asrManager.transcribe(audioBuffer)
```

### Ollama API (Local)
```
POST http://localhost:11434/api/generate
{
  "model": "llama3.2:3b",
  "prompt": "...",
  "stream": false
}
```

### OpenRouter API (Cloud)
```
POST https://openrouter.ai/api/v1/chat/completions
Authorization: Bearer $OPENROUTER_API_KEY
{
  "model": "groq/llama-3.1-70b-versatile",
  "messages": [...]
}
```

### Text Injection Pattern
1. Save current clipboard
2. Set clipboard to text
3. Sleep 50ms
4. Simulate Cmd+V
5. Sleep 100ms
6. Restore original clipboard

### Global Hotkey (CGEvent Tap)
Use `CGEvent.tapCreate()` for global hotkey detection. Hold-to-record means:
- Key down → start recording
- Key up → stop recording, process, inject

## Critical Implementation Gotchas

These patterns are learned from FluidVoice — ignore them at your peril:

### 1. AVAudioEngine Storage
**Problem:** Storing AVAudioEngine as `@Published` property causes EXC_BAD_ACCESS crashes.
**Solution:** Store as `AnyObject?` to hide from Combine's reflection:
```swift
private var engineStorage: AnyObject?
private var engine: AVAudioEngine {
    if let existing = engineStorage as? AVAudioEngine { return existing }
    let created = AVAudioEngine()
    engineStorage = created
    return created
}
```

### 2. Thread-Safe Audio Buffer
**Problem:** Concurrent access to audio buffer causes crashes.
**Solution:** Use NSLock-protected buffer:
```swift
final class ThreadSafeAudioBuffer {
    private var buffer: [Float] = []
    private let lock = NSLock()

    func append(_ samples: [Float]) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(contentsOf: samples)
    }
}
```

### 3. Serialize FluidAudio Calls
**Problem:** FluidAudio/CoreML cannot handle concurrent transcriptions.
**Solution:** Use an actor to serialize:
```swift
private actor TranscriptionExecutor {
    func run<T>(_ op: @escaping () async throws -> T) async throws -> T {
        return try await op()
    }
}
// Usage: try await executor.run { asrManager.transcribe(samples) }
```

### 4. CGEvent Tap Health Monitoring
**Problem:** macOS silently disables event taps after timeout.
**Solution:** Periodically check and re-enable:
```swift
if !CGEvent.tapIsEnabled(tap: eventTap) {
    CGEvent.tapEnable(tap: eventTap, enable: true)
}
```

### 5. Multi-Strategy Text Injection
**Problem:** Single injection method doesn't work in all apps.
**Solution:** Try multiple strategies in order:
1. CGEvent unicode to target PID
2. Accessibility API (kAXValueAttribute)
3. Clipboard + Cmd+V (fallback)

### 6. Lazy Service Initialization
**Problem:** Initializing audio services too early causes crashes.
**Solution:** Delay initialization until UI is ready (1-2 second delay after app launch).

## Testing Strategy

- **Manual verification:** All features verified manually using steps in features.json
- **Console logging:** Verify flows during development
- **Automated tests:** Can be added later if needed (XCTest)

## Progress Tracking

- `features.json` — Source of truth for what's done/not done
- `claude-progress.txt` — Human-readable session log
- Git history — Implicit progress tracking

When in doubt, check these files to understand current state.
