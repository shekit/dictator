import Foundation
import FluidAudio

/// Actor to serialize FluidAudio/CoreML calls (cannot handle concurrent transcriptions)
private actor TranscriptionExecutor {
    func run<T>(_ op: @escaping () async throws -> T) async throws -> T {
        return try await op()
    }
}

/// Transcription state for UI updates
enum TranscriptionState: Equatable {
    case idle
    case loadingModel
    case transcribing
    case error(String)
}

/// Service that handles speech-to-text transcription using FluidAudio
@MainActor
final class TranscriptionService: ObservableObject {

    static let shared = TranscriptionService()

    @Published private(set) var state: TranscriptionState = .idle
    @Published private(set) var isModelLoaded: Bool = false

    private var asrManager: AsrManager?
    private let executor = TranscriptionExecutor()

    private init() {}

    /// Prepare the ASR models (checks bundled models first, then downloads if needed)
    func prepareModels() async throws {
        guard !isModelLoaded else {
            print("[TranscriptionService] Models already loaded")
            return
        }

        state = .loadingModel
        print("[TranscriptionService] Starting model preparation...")

        do {
            // First, try to load from app bundle (for distribution)
            let bundledModelsPath = getBundledModelsPath()
            let models: AsrModels

            if AsrModels.modelsExist(at: bundledModelsPath, version: .v2) {
                print("[TranscriptionService] Loading models from app bundle...")
                models = try await AsrModels.load(from: bundledModelsPath, version: .v2)
                print("[TranscriptionService] Models loaded from app bundle")
            } else {
                // Fallback: download models (first launch without bundled models)
                print("[TranscriptionService] Bundled models not found, downloading...")
                print("[TranscriptionService] ⏳ This may take 2-5 minutes on first launch...")
                models = try await AsrModels.downloadAndLoad(version: .v2)
                print("[TranscriptionService] Models downloaded to cache")
            }

            // Initialize AsrManager
            let manager = AsrManager(config: ASRConfig.default)
            try await manager.initialize(models: models)

            self.asrManager = manager
            self.isModelLoaded = true
            self.state = .idle

            print("[TranscriptionService] ASR model loaded successfully")
        } catch {
            self.state = .error("Failed to load ASR model: \(error.localizedDescription)")
            print("[TranscriptionService] ❌ Error loading models: \(error)")
            throw error
        }
    }

    /// Get path to bundled models in app bundle
    private func getBundledModelsPath() -> URL {
        if let bundlePath = Bundle.main.resourceURL?.appendingPathComponent("FluidAudio/models/v2") {
            return bundlePath
        }
        // Fallback to default cache if bundle path not found
        return AsrModels.defaultCacheDirectory(for: .v2)
    }

    /// Check if models exist on disk (for determining first-run state)
    func modelsExistOnDisk() -> Bool {
        let cacheDir = AsrModels.defaultCacheDirectory(for: .v2)
        return AsrModels.modelsExist(at: cacheDir, version: .v2)
    }

    /// Transcribe audio samples to text
    /// - Parameter samples: Audio samples at 16kHz sample rate as Float array
    /// - Returns: Transcribed text, or empty string if transcription fails
    func transcribe(_ samples: [Float]) async throws -> String {
        guard let manager = asrManager else {
            throw TranscriptionError.notInitialized
        }

        // Handle empty or very short recordings
        guard samples.count >= 1600 else { // At least 100ms of audio at 16kHz
            print("[TranscriptionService] Audio too short (\(samples.count) samples), returning empty")
            return ""
        }

        state = .transcribing
        print("[TranscriptionService] Starting transcription of \(samples.count) samples...")

        do {
            // Serialize FluidAudio calls using the actor
            let result = try await executor.run {
                try await manager.transcribe(samples, source: .microphone)
            }

            state = .idle
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            print("[TranscriptionService] Transcription complete: '\(text)'")
            return text
        } catch {
            state = .error("Transcription failed: \(error.localizedDescription)")
            print("[TranscriptionService] Transcription error: \(error)")
            throw error
        }
    }

    /// Cleanup resources
    func cleanup() {
        asrManager?.cleanup()
        asrManager = nil
        isModelLoaded = false
        state = .idle
        print("[TranscriptionService] Cleaned up")
    }
}

enum TranscriptionError: LocalizedError {
    case notInitialized
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "ASR models not loaded. Call prepareModels() first."
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}
