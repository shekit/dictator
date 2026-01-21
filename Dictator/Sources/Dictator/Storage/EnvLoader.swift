import Foundation

/// Manages app configuration.
/// Only uses UserDefaults - no .env file loading to avoid permission prompts.
@MainActor
final class EnvLoader {
    static let shared = EnvLoader()

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Load configuration (no-op for now, kept for compatibility).
    func load() {
        print("[EnvLoader] Using UserDefaults for configuration (no .env file)")
    }

    /// Get OpenRouter API key from UserDefaults.
    var openRouterAPIKey: String? {
        let key = UserDefaults.standard.string(forKey: "openRouterAPIKey")
        return key?.isEmpty == false ? key : nil
    }

    /// Get Ollama host URL (defaults to localhost:11434).
    var ollamaHost: String {
        UserDefaults.standard.string(forKey: "ollamaHost") ?? "http://localhost:11434"
    }

    /// Check if OpenRouter API key is configured.
    var hasOpenRouterKey: Bool {
        guard let key = openRouterAPIKey else { return false }
        return !key.isEmpty && key.hasPrefix("sk-or-")
    }
}
