import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var recordingService: RecordingService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load environment variables first
        EnvLoader.shared.load()

        // Log API key status
        if EnvLoader.shared.hasOpenRouterKey {
            print("[App] OpenRouter API key loaded")
        } else {
            print("[App] No OpenRouter API key configured")
            print("[App] Create a .env file with OPENROUTER_API_KEY=sk-or-...")
        }

        // Create status bar controller
        statusBarController = StatusBarController { [weak self] in
            self?.terminate()
        }

        // Create recording service
        recordingService = RecordingService()

        // Connect status bar to recording service for state updates
        if let service = recordingService {
            statusBarController?.setRecordingService(service)
            statusBarController?.setLLMService(LLMService.shared)

            // Set up callback for when transcription completes
            service.onTranscriptionComplete = { rawText, processedText, duration, wasProcessed in
                let status = wasProcessed ? "LLM cleaned" : "raw"
                print("[App] Transcription complete (\(status)) - '\(processedText)' (\(String(format: "%.2f", duration))s)")
            }
        }

        // CRITICAL: Delay service initialization to avoid race conditions
        // Audio services need UI to be fully ready before initializing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.recordingService?.initialize()

            // Start loading ASR models in background
            // First recording will wait if not ready, but we start early for faster first use
            Task {
                do {
                    print("[App] Starting ASR model preparation...")
                    try await TranscriptionService.shared.prepareModels()
                    print("[App] ASR models ready")
                } catch {
                    print("[App] Failed to prepare ASR models: \(error)")
                    // Models will be loaded on first transcription attempt
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        TranscriptionService.shared.cleanup()
        recordingService?.shutdown()
        recordingService = nil
        statusBarController = nil
    }

    private func terminate() {
        NSApp.terminate(nil)
    }
}
