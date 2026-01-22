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
    @Published private(set) var isHandsFreeMode: Bool = false

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
            // Only start recording in push-to-talk mode (not hands-free)
            if !isHandsFreeMode {
                startRecording()
            }
        case .keyUp:
            // Only stop on key up in push-to-talk mode (not hands-free)
            if !isHandsFreeMode {
                stopRecording()
            } else {
                print("[RecordingService] Hands-free mode: ignoring fn release")
            }
        case .cancelled:
            cancelRecording()
            isHandsFreeMode = false
            hotkeyManager?.isInHandsFreeMode = false
        case .handsFreeToggle:
            handleHandsFreeToggle()
        }
    }

    private func handleHandsFreeToggle() {
        if isHandsFreeMode, case .recording = state {
            // Already in hands-free mode and recording - stop recording
            print("[RecordingService] Hands-free mode: stopping recording")
            isHandsFreeMode = false
            hotkeyManager?.isInHandsFreeMode = false
            stopRecording()
        } else if case .recording = state {
            // Recording (from fn press), switch to hands-free mode
            isHandsFreeMode = true
            hotkeyManager?.isInHandsFreeMode = true
            print("[RecordingService] Switched to hands-free mode - press space to stop")
        } else if case .idle = state {
            // Not recording yet, start in hands-free mode
            isHandsFreeMode = true
            hotkeyManager?.isInHandsFreeMode = true
            startRecording()
            print("[RecordingService] Started recording in hands-free mode - press space to stop")
        }
    }

    private func cancelRecording() {
        guard case .recording = state else {
            print("[RecordingService] Cannot cancel - not recording (current state: \(state))")
            return
        }

        // Stop recording and cancel streaming
        _ = audioRecorder.stopRecording()
        audioRecorder.onAudioBuffer = nil
        Task { await transcriptionService.cancelStreaming() }
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

        // Start streaming transcription in background
        Task {
            do {
                // Ensure models are loaded
                if !transcriptionService.isModelLoaded {
                    print("[RecordingService] Models not loaded, loading now...")
                    try await transcriptionService.prepareModels()
                }

                // Start streaming session
                try await transcriptionService.startStreaming()

                // Set up audio buffer callback to stream to transcription service
                audioRecorder.onAudioBuffer = { [weak self] buffer in
                    Task { [weak self] in
                        await self?.transcriptionService.streamAudio(buffer)
                    }
                }

                // Now start recording
                await MainActor.run {
                    self.audioRecorder.startRecording()
                    self.state = .recording
                    self.soundEffectService.playRecordingStart()
                    print("[RecordingService] Recording started (with streaming)")
                }
            } catch {
                await MainActor.run {
                    let errorMsg = "Failed to start: \(error.localizedDescription)"
                    self.state = .error(errorMsg)
                    self.notificationService.showError(message: errorMsg)
                    print("[RecordingService] Start error: \(error)")
                }
            }
        }
    }

    private func stopRecording() {
        guard case .recording = state else {
            print("[RecordingService] Cannot stop recording - not recording (current state: \(state))")
            return
        }

        // Stop audio recording
        guard let result = audioRecorder.stopRecording() else {
            audioRecorder.onAudioBuffer = nil
            Task { await transcriptionService.cancelStreaming() }
            state = .idle
            print("[RecordingService] No audio captured")
            return
        }

        // Clear the streaming callback
        audioRecorder.onAudioBuffer = nil

        lastRecordingDuration = result.duration
        lastBufferSize = result.samples.count
        soundEffectService.playRecordingStop()

        print("[RecordingService] Recording stopped - Duration: \(String(format: "%.2f", result.duration))s")

        // Finish streaming transcription (should be fast since audio was processed in chunks)
        finishStreamingTranscription(duration: result.duration)
    }

    private func finishStreamingTranscription(duration: TimeInterval) {
        state = .transcribing

        Task {
            // Safety timeout
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(90))
                if case .idle = self.state { return }
                print("[RecordingService] ⚠️ Safety timeout triggered")
                await MainActor.run {
                    self.state = .idle
                    self.notificationService.showError(
                        title: "Processing Timeout",
                        message: "The request took too long and was cancelled."
                    )
                }
            }

            do {
                // Finish streaming and get final text (should be fast!)
                let rawText = try await transcriptionService.finishStreaming()
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
                    print("[RecordingService] Using raw transcription")
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

                timeoutTask.cancel()
                state = .idle

            } catch {
                timeoutTask.cancel()
                let errorMsg = "Transcription failed: \(error.localizedDescription)"
                state = .error(errorMsg)
                notificationService.showError(title: "Transcription Failed", message: error.localizedDescription)
                print("[RecordingService] Transcription error: \(error)")

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
