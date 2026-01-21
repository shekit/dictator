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
    @Published private(set) var lastProcessedText: String = ""

    // MARK: - Properties

    private var hotkeyManager: GlobalHotkeyManager?
    private let audioRecorder: AudioRecorder
    private let transcriptionService = TranscriptionService.shared
    private let textInjectionService = TextInjectionService.shared
    private let llmService = LLMService.shared
    private let soundEffectService = SoundEffectService.shared
    private let notificationService = NotificationService.shared
    private var isInitialized = false

    /// Callback when transcription completes (called after text injection)
    /// Parameters: (raw text, processed text, duration, was LLM processed)
    var onTranscriptionComplete: ((String, String, TimeInterval, Bool) -> Void)?

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
            let errorMsg = "Microphone permission required"
            state = .error(errorMsg)
            notificationService.showError(message: errorMsg)
            return
        }

        if audioRecorder.permissionStatus == .denied {
            let errorMsg = "Microphone access denied. Please enable in System Settings."
            state = .error(errorMsg)
            notificationService.showError(message: errorMsg)
            print("[RecordingService] Microphone permission denied - cannot record")
            return
        }

        audioRecorder.startRecording()
        state = .recording
        soundEffectService.playRecordingStart()
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
        soundEffectService.playRecordingStop()

        print("[RecordingService] Recording stopped - Duration: \(String(format: "%.2f", result.duration))s, Samples: \(result.samples.count)")

        // Start transcription
        transcribeAudio(samples: result.samples, duration: result.duration)
    }

    private func transcribeAudio(samples: [Float], duration: TimeInterval) {
        state = .transcribing

        Task {
            // Safety timeout: if processing takes more than 90 seconds, force reset to idle
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(90))
                if case .idle = self.state {
                    // Already completed successfully
                    return
                }
                print("[RecordingService] ⚠️ Safety timeout triggered - forcing reset to idle")
                await MainActor.run {
                    self.state = .idle
                    self.notificationService.showError(
                        title: "Processing Timeout",
                        message: "The request took too long and was cancelled. Try again or switch to a different mode."
                    )
                }
            }

            do {
                // Ensure models are loaded
                if !transcriptionService.isModelLoaded {
                    print("[RecordingService] Models not loaded, loading now...")
                    try await transcriptionService.prepareModels()
                }

                // Transcribe
                let rawText = try await transcriptionService.transcribe(samples)
                lastTranscription = rawText

                print("[RecordingService] Transcription complete: '\(rawText)'")

                // Skip injection if text is empty
                guard !rawText.isEmpty else {
                    print("[RecordingService] Empty transcription, skipping injection")
                    timeoutTask.cancel()
                    state = .idle
                    return
                }

                // LLM Processing (if enabled)
                state = .processing
                let (processedText, wasProcessed) = await llmService.processTranscription(rawText)
                lastProcessedText = processedText

                if wasProcessed {
                    print("[RecordingService] LLM processed: '\(processedText)'")
                } else {
                    print("[RecordingService] Using raw transcription (LLM disabled or failed)")
                }

                // Inject text at cursor position
                state = .injecting
                let injected = await textInjectionService.injectText(processedText)

                if injected {
                    print("[RecordingService] Text injected successfully")
                } else {
                    print("[RecordingService] Text injection failed")
                }

                // Notify callback
                onTranscriptionComplete?(rawText, processedText, duration, wasProcessed)

                // Cancel timeout and return to idle
                timeoutTask.cancel()
                state = .idle

            } catch {
                timeoutTask.cancel()
                let errorMsg = "Transcription failed: \(error.localizedDescription)"
                state = .error(errorMsg)
                notificationService.showError(title: "Transcription Failed", message: error.localizedDescription)
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
