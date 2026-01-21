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
        case transcribing
        case processing
        case injecting
        case error(String)
    }

    // MARK: - Published Properties

    @Published private(set) var state: State = .idle
    @Published private(set) var lastRecordingDuration: TimeInterval = 0
    @Published private(set) var lastBufferSize: Int = 0
    @Published private(set) var lastTranscription: String = ""

    // MARK: - Properties

    private var hotkeyManager: GlobalHotkeyManager?
    private let audioRecorder: AudioRecorder
    private let transcriptionService = TranscriptionService.shared
    private let textInjectionService = TextInjectionService.shared
    private var isInitialized = false

    /// Callback when transcription completes (called after text injection)
    var onTranscriptionComplete: ((String, TimeInterval) -> Void)?

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
        case .cancelled:
            cancelRecording()
        }
    }

    private func cancelRecording() {
        guard case .recording = state else {
            print("[RecordingService] Cannot cancel - not recording (current state: \(state))")
            return
        }

        // Stop recording but discard the audio
        _ = audioRecorder.stopRecording()
        state = .idle
        print("[RecordingService] Recording cancelled (fn + other key)")
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

        print("[RecordingService] Recording stopped - Duration: \(String(format: "%.2f", result.duration))s, Samples: \(result.samples.count)")

        // Start transcription
        transcribeAudio(samples: result.samples, duration: result.duration)
    }

    private func transcribeAudio(samples: [Float], duration: TimeInterval) {
        state = .transcribing

        Task {
            do {
                // Ensure models are loaded
                if !transcriptionService.isModelLoaded {
                    print("[RecordingService] Models not loaded, loading now...")
                    try await transcriptionService.prepareModels()
                }

                // Transcribe
                let text = try await transcriptionService.transcribe(samples)
                lastTranscription = text

                print("[RecordingService] Transcription complete: '\(text)'")

                // Skip injection if text is empty
                guard !text.isEmpty else {
                    print("[RecordingService] Empty transcription, skipping injection")
                    state = .idle
                    return
                }

                // Inject text at cursor position
                state = .injecting
                let injected = await textInjectionService.injectText(text)

                if injected {
                    print("[RecordingService] Text injected successfully")
                } else {
                    print("[RecordingService] Text injection failed")
                }

                // Notify callback
                onTranscriptionComplete?(text, duration)

                // Return to idle
                state = .idle

            } catch {
                state = .error("Transcription failed: \(error.localizedDescription)")
                print("[RecordingService] Transcription error: \(error)")

                // Return to idle after a brief delay so user sees error
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if case .error = self.state {
                        self.state = .idle
                    }
                }
            }
        }
    }
}
