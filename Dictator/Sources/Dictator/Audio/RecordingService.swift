import AppKit
import Combine

/// Coordinates hotkey detection with audio recording.
/// Manages the hold-to-record workflow.
@MainActor
final class RecordingService: ObservableObject {
    // MARK: - Types

    enum State {
        case idle
        case recording
        case processing
        case error(String)
    }

    // MARK: - Published Properties

    @Published private(set) var state: State = .idle
    @Published private(set) var lastRecordingDuration: TimeInterval = 0
    @Published private(set) var lastBufferSize: Int = 0

    // MARK: - Properties

    private var hotkeyManager: GlobalHotkeyManager?
    private let audioRecorder: AudioRecorder
    private var isInitialized = false

    /// Callback when recording completes with audio samples
    var onRecordingComplete: (([Float], TimeInterval) -> Void)?

    // MARK: - Initialization

    init() {
        audioRecorder = AudioRecorder()
    }

    // MARK: - Public Methods

    /// Initialize the recording service. Call this 1-2 seconds after app launch.
    func initialize() {
        guard !isInitialized else { return }
        isInitialized = true

        // Initialize audio recorder first
        audioRecorder.initialize()

        // Setup hotkey manager with handler
        hotkeyManager = GlobalHotkeyManager { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleHotkeyEvent(event)
            }
        }

        // Start listening for hotkeys
        hotkeyManager?.start()

        print("[RecordingService] Initialized")
    }

    /// Stop the recording service and cleanup.
    func shutdown() {
        hotkeyManager?.stop()
        hotkeyManager = nil
        isInitialized = false
        print("[RecordingService] Shutdown")
    }

    /// Request microphone permission.
    func requestMicrophoneAccess() {
        audioRecorder.requestMicrophoneAccess()
    }

    /// Open microphone settings in System Preferences.
    func openMicrophoneSettings() {
        audioRecorder.openMicrophoneSettings()
    }

    /// Get current microphone permission status.
    var microphonePermissionStatus: AudioRecorder.PermissionStatus {
        audioRecorder.permissionStatus
    }

    // MARK: - Private Methods

    private func handleHotkeyEvent(_ event: GlobalHotkeyManager.HotkeyEvent) {
        switch event {
        case .keyDown:
            startRecording()
        case .keyUp:
            stopRecording()
        }
    }

    private func startRecording() {
        guard case .idle = state else {
            print("[RecordingService] Cannot start recording - not idle (current state: \(state))")
            return
        }

        // Check permission first
        if audioRecorder.permissionStatus == .notDetermined {
            audioRecorder.requestMicrophoneAccess()
            state = .error("Microphone permission required")
            return
        }

        if audioRecorder.permissionStatus == .denied {
            state = .error("Microphone access denied. Please enable in System Settings.")
            print("[RecordingService] Microphone permission denied - cannot record")
            return
        }

        audioRecorder.startRecording()
        state = .recording
        print("[RecordingService] Recording started")
    }

    private func stopRecording() {
        guard case .recording = state else {
            print("[RecordingService] Cannot stop recording - not recording (current state: \(state))")
            return
        }

        guard let result = audioRecorder.stopRecording() else {
            state = .idle
            print("[RecordingService] No audio captured")
            return
        }

        lastRecordingDuration = result.duration
        lastBufferSize = result.samples.count
        state = .processing

        print("[RecordingService] Recording stopped - Duration: \(String(format: "%.2f", result.duration))s, Samples: \(result.samples.count)")

        // Notify callback with recorded audio
        onRecordingComplete?(result.samples, result.duration)

        // For now, return to idle (later phases will handle transcription)
        state = .idle
    }
}
