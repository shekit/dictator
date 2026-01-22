import AVFoundation
import AppKit

/// Thread-safe audio buffer for concurrent sample access.
final class ThreadSafeAudioBuffer {
    private var buffer: [Float] = []
    private let lock = NSLock()

    func append(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(contentsOf: samples)
    }

    func getAndClear() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let data = buffer
        buffer.removeAll(keepingCapacity: true)
        return data
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll(keepingCapacity: true)
    }
}

/// Manages audio recording from the microphone using AVAudioEngine.
@MainActor
final class AudioRecorder: ObservableObject {
    // MARK: - Types

    enum RecordingState {
        case idle
        case recording
        case error(String)
    }

    enum PermissionStatus {
        case notDetermined
        case authorized
        case denied
    }

    // MARK: - Published Properties

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var permissionStatus: PermissionStatus = .notDetermined

    // MARK: - Private Properties

    /// Critical: Store AVAudioEngine as AnyObject to avoid Combine reflection crashes
    private var engineStorage: AnyObject?
    private var engine: AVAudioEngine {
        if let existing = engineStorage as? AVAudioEngine {
            return existing
        }
        let created = AVAudioEngine()
        engineStorage = created
        return created
    }

    private let audioBuffer = ThreadSafeAudioBuffer()
    private let sampleRate: Double = 16000.0
    private var recordingStartTime: Date?
    private var isInitialized = false

    /// Callback for streaming audio buffers during recording
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    // MARK: - Initialization

    init() {
        // CRITICAL: Do NOT call any AVFoundation APIs here
        // Wait for initialize() to be called after UI is ready
    }

    // MARK: - Public Methods

    /// Initialize the audio recorder. Call this 1-2 seconds after app launch.
    func initialize() {
        guard !isInitialized else { return }
        isInitialized = true

        checkMicrophonePermission()
    }

    /// Request microphone access from the user.
    func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.permissionStatus = granted ? .authorized : .denied
                if granted {
                    print("[Audio] Microphone permission granted")
                } else {
                    print("[Audio] Microphone permission denied")
                    self?.state = .error("Microphone access denied")
                }
            }
        }
    }

    /// Start recording audio from the microphone.
    func startRecording() {
        guard permissionStatus == .authorized else {
            if permissionStatus == .notDetermined {
                requestMicrophoneAccess()
            } else {
                state = .error("Microphone access denied. Please enable in System Settings.")
            }
            return
        }

        do {
            audioBuffer.clear()
            try setupAndStartEngine()
            recordingStartTime = Date()
            state = .recording
            print("[Audio] Recording started")
        } catch {
            state = .error("Failed to start recording: \(error.localizedDescription)")
            print("[Audio] Failed to start recording: \(error)")
        }
    }

    /// Stop recording and return the captured audio samples.
    func stopRecording() -> (samples: [Float], duration: TimeInterval)? {
        guard case .recording = state else { return nil }

        stopEngine()

        let samples = audioBuffer.getAndClear()
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0

        state = .idle
        recordingStartTime = nil

        print("[Audio] Recording stopped - Buffer size: \(samples.count) samples, Duration: \(String(format: "%.2f", duration))s")

        return (samples, duration)
    }

    /// Open System Settings to the microphone privacy pane.
    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Private Methods

    private func checkMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            permissionStatus = .authorized
            print("[Audio] Microphone permission already granted")
        case .denied, .restricted:
            permissionStatus = .denied
            print("[Audio] Microphone permission denied")
        case .notDetermined:
            permissionStatus = .notDetermined
            print("[Audio] Microphone permission not determined")
        @unknown default:
            permissionStatus = .notDetermined
        }
    }

    private func setupAndStartEngine() throws {
        let audioEngine = engine
        let inputNode = audioEngine.inputNode

        // Get the native format of the input node
        let nativeFormat = inputNode.inputFormat(forBus: 0)

        // Create our target format (16kHz mono Float32 for speech recognition)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create target audio format"])
        }

        // Create a converter if sample rates differ
        let needsConversion = nativeFormat.sampleRate != sampleRate

        // Install tap on the input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            if needsConversion {
                // Convert to target format
                if let convertedBuffer = self.convertBuffer(buffer, from: nativeFormat, to: targetFormat) {
                    self.processAudioBuffer(convertedBuffer)
                    // Stream to transcription service
                    self.onAudioBuffer?(convertedBuffer)
                }
            } else {
                self.processAudioBuffer(buffer)
                // Stream to transcription service
                self.onAudioBuffer?(buffer)
            }
        }

        // Prepare and start the engine
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func convertBuffer(_ buffer: AVAudioPCMBuffer, from sourceFormat: AVAudioFormat, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            return nil
        }

        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / sourceFormat.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
            return nil
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            print("[Audio] Conversion error: \(error)")
            return nil
        }

        return outputBuffer
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        audioBuffer.append(samples)
    }

    private func stopEngine() {
        let audioEngine = engine
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        // Deallocate engine to ensure clean state for next recording
        engineStorage = nil
    }
}
