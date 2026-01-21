import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var recordingService: RecordingService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar controller
        statusBarController = StatusBarController { [weak self] in
            self?.terminate()
        }

        // Create recording service
        recordingService = RecordingService()

        // Connect status bar to recording service for state updates
        if let service = recordingService {
            statusBarController?.setRecordingService(service)

            // Set up callback for when recording completes
            service.onRecordingComplete = { samples, duration in
                print("[App] Recording complete - \(samples.count) samples, \(String(format: "%.2f", duration))s")
                // Future phases will handle transcription here
            }
        }

        // CRITICAL: Delay service initialization to avoid race conditions
        // Audio services need UI to be fully ready before initializing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.recordingService?.initialize()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        recordingService?.shutdown()
        recordingService = nil
        statusBarController = nil
    }

    private func terminate() {
        NSApp.terminate(nil)
    }
}
