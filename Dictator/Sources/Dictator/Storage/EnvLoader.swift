import Foundation

/// Loads environment variables from a .env file.
/// Supports standard .env format: KEY=value (one per line, # comments)
@MainActor
final class EnvLoader {
    static let shared = EnvLoader()

    // MARK: - Properties

    private var loadedValues: [String: String] = [:]
    private var isLoaded = false

    /// Path to the .env file (in app's container or project root)
    private var envFilePath: URL? {
        // Look in multiple locations:
        // 1. First, check the executable's directory (for dev builds)
        // 2. Then check home directory
        // 3. Finally check ~/Documents/Dictator/

        let paths = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".env"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".env"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents")
                .appendingPathComponent("Dictator")
                .appendingPathComponent(".env")
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
        }

        return nil
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Load environment variables from .env file.
    /// Call this once at app startup.
    func load() {
        guard !isLoaded else { return }
        isLoaded = true

        guard let path = envFilePath else {
            print("[EnvLoader] No .env file found")
            print("[EnvLoader] Searched in:")
            print("  - App bundle directory")
            print("  - Home directory (~/.env)")
            print("  - ~/Documents/Dictator/.env")
            return
        }

        do {
            let contents = try String(contentsOf: path, encoding: .utf8)
            loadedValues = parse(contents)
            print("[EnvLoader] Loaded \(loadedValues.count) variables from \(path.path)")
        } catch {
            print("[EnvLoader] Failed to read .env file: \(error.localizedDescription)")
        }
    }

    /// Get a value from the loaded .env file.
    /// Falls back to process environment if not found in .env.
    func get(_ key: String) -> String? {
        // First check loaded .env values
        if let value = loadedValues[key] {
            return value
        }

        // Fall back to process environment (for debug/testing)
        return ProcessInfo.processInfo.environment[key]
    }

    /// Get OpenRouter API key.
    var openRouterAPIKey: String? {
        self.get("OPENROUTER_API_KEY")
    }

    /// Get Ollama host URL (defaults to localhost:11434).
    var ollamaHost: String {
        self.get("OLLAMA_HOST") ?? "http://localhost:11434"
    }

    /// Check if OpenRouter API key is configured.
    var hasOpenRouterKey: Bool {
        guard let key = openRouterAPIKey else { return false }
        return !key.isEmpty && key.hasPrefix("sk-or-")
    }

    /// Get path to the .env file for user reference.
    var envFileLocation: String? {
        envFilePath?.path
    }

    // MARK: - Private Methods

    private func parse(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]

        let lines = contents.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Parse KEY=value format
            if let equalIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                var value = String(trimmed[trimmed.index(after: equalIndex)...])
                    .trimmingCharacters(in: .whitespaces)

                // Remove surrounding quotes if present
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }

                if !key.isEmpty {
                    result[key] = value
                }
            }
        }

        return result
    }
}
