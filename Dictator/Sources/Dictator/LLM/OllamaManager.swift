import Foundation

/// Manages Ollama server lifecycle (starting/stopping).
@MainActor
final class OllamaManager {
    // MARK: - Singleton

    static let shared = OllamaManager()

    // MARK: - Properties

    private var ollamaProcess: Process?

    /// Check if the Ollama server is running (managed by this app).
    var isServerRunning: Bool {
        return ollamaProcess?.isRunning == true
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Attempt to start Ollama server in the background.
    /// Returns success/failure with error message if failed.
    func startOllamaServer() -> (success: Bool, error: String?) {
        // Check if already running
        if ollamaProcess?.isRunning == true {
            return (true, nil)
        }

        // Find Ollama executable
        guard let ollamaPath = findOllamaExecutable() else {
            return (false, "Ollama not found. Install it from ollama.ai")
        }

        // Launch ollama serve
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ollamaPath)
        process.arguments = ["serve"]

        // Redirect output to avoid blocking
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            ollamaProcess = process
            print("[OllamaManager] Started Ollama server at \(ollamaPath)")
            return (true, nil)
        } catch {
            print("[OllamaManager] Failed to start Ollama: \(error.localizedDescription)")
            return (false, "Failed to start Ollama: \(error.localizedDescription)")
        }
    }

    /// Stop Ollama server if it was started by this manager.
    func stopOllamaServer() {
        if let process = ollamaProcess, process.isRunning {
            process.terminate()
            ollamaProcess = nil
            print("[OllamaManager] Stopped Ollama server")
        }
    }

    // MARK: - Private Methods

    /// Find Ollama executable in common locations.
    private func findOllamaExecutable() -> String? {
        let commonPaths = [
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
            "/usr/bin/ollama",
            "~/usr/local/bin/ollama".expandingTildeInPath,
        ]

        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try using 'which' command as fallback
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = ["ollama"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            print("[OllamaManager] Failed to run 'which' command: \(error)")
        }

        return nil
    }
}

// MARK: - String Extension

private extension String {
    var expandingTildeInPath: String {
        return NSString(string: self).expandingTildeInPath
    }
}
