import AppKit

/// Plays system sound effects for UI feedback.
/// Uses macOS built-in sounds for a native experience.
final class SoundEffectService {
    // MARK: - Singleton

    static let shared = SoundEffectService()

    // MARK: - Sound Names

    private enum SystemSound: String {
        case recordingStart = "Tink"      // Subtle click for recording start
        case recordingStop = "Pop"        // Clean pop for recording stop
        case error = "Basso"              // Deep tone for errors
    }

    // MARK: - Properties

    private var soundsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "soundEffectsEnabled")
    }

    // MARK: - Initialization

    private init() {
        // Enable sounds by default on first run
        if UserDefaults.standard.object(forKey: "soundEffectsEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "soundEffectsEnabled")
        }
    }

    // MARK: - Public Methods

    /// Play sound when recording starts.
    func playRecordingStart() {
        playSound(.recordingStart)
    }

    /// Play sound when recording stops.
    func playRecordingStop() {
        playSound(.recordingStop)
    }

    /// Play sound for errors.
    func playError() {
        playSound(.error)
    }

    /// Toggle sound effects on/off.
    func setSoundsEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "soundEffectsEnabled")
    }

    // MARK: - Private Methods

    private func playSound(_ sound: SystemSound) {
        guard soundsEnabled else { return }

        // Play system sound asynchronously (non-blocking)
        DispatchQueue.global(qos: .userInitiated).async {
            NSSound(named: sound.rawValue)?.play()
        }
    }
}
