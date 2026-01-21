import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var recordingService: RecordingService?
    private var onboardingWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load configuration
        EnvLoader.shared.load()

        // Log API key status
        if EnvLoader.shared.hasOpenRouterKey {
            print("[App] OpenRouter API key configured")
        } else {
            print("[App] No OpenRouter API key configured - add one in Settings")
        }

        // Create status bar controller
        statusBarController = StatusBarController { [weak self] in
            self?.terminate()
        }

        // Check if this is first run or onboarding was interrupted (DO NOT create RecordingService yet to avoid permission prompts)
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        if !hasCompletedOnboarding {
            // Show onboarding on next run loop after UI is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showOnboarding()
            }
        } else {
            // Only initialize if onboarding is complete
            // CRITICAL: Delay service initialization to avoid race conditions
            // Audio services need UI to be fully ready before initializing
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.initializeServices()
            }
        }

        // Pass onboarding status to status bar for menu item
        statusBarController?.setOnboardingComplete(hasCompletedOnboarding)
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

    private func initializeServices() {
        // Create recording service
        recordingService = RecordingService()

        // Connect status bar to recording service for state updates
        if let service = recordingService {
            statusBarController?.setRecordingService(service)
            statusBarController?.setLLMService(LLMService.shared)

            // Set up callback for when transcription completes
            service.onTranscriptionComplete = { [weak statusBarController] rawText, processedText, duration, wasProcessed in
                let status = wasProcessed ? "LLM cleaned" : "raw"
                print("[App] Transcription complete (\(status)) - '\(processedText)' (\(String(format: "%.2f", duration))s)")

                // Record stats
                let stats = StatsService.shared.recordTranscription(text: processedText, duration: duration)

                // Update status bar with today's stats
                statusBarController?.updateTodayStats()

                // Log to file
                let llmService = LLMService.shared
                let mode: String
                let model: String

                switch llmService.processingMode {
                case .cloud:
                    mode = "cloud"
                    model = llmService.selectedCloudModel
                case .local:
                    mode = "local"
                    model = llmService.selectedLocalModel
                case .off:
                    mode = "off"
                    model = "none"
                }

                Task {
                    await TranscriptionLogger.shared.log(
                        rawText: rawText,
                        cleanedText: processedText,
                        wordCount: stats.wordCount,
                        duration: stats.duration,
                        wpm: stats.wpm,
                        mode: mode,
                        model: model
                    )
                }
            }

            // Initialize the service
            service.initialize()
        }

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

    /// Show onboarding window (can be called from menu or on launch)
    func showOnboarding() {
        // If already showing, just bring to front
        if let existingWindow = onboardingWindowController?.window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = OnboardingWindow { [weak self] in
            // Mark onboarding as complete
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            print("[App] Onboarding completed")

            // Close onboarding window
            self?.onboardingWindowController?.close()
            self?.onboardingWindowController = nil

            // Update menu item visibility
            self?.statusBarController?.setOnboardingComplete(true)

            // Initialize services now that onboarding is complete (only if not already initialized)
            if self?.recordingService == nil {
                self?.initializeServices()
            }
        }

        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Dictator"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 600, height: 450))
        window.center()
        window.level = .floating  // Keep on top

        // Set delegate to track window closing
        window.delegate = self

        let windowController = NSWindowController(window: window)
        onboardingWindowController = windowController

        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == onboardingWindowController?.window else {
            return
        }

        // Check if onboarding was actually completed
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        if !hasCompletedOnboarding {
            // User closed window without completing
            print("[App] Onboarding dismissed")

            // Initialize services if needed (so app is still usable)
            if recordingService == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.initializeServices()
                }
            }
        }

        onboardingWindowController = nil
    }
}
