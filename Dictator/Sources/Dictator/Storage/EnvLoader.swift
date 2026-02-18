import Foundation

/// Manages app configuration.
/// Uses UserDefaults for app configuration.
@MainActor
final class EnvLoader {
    static let shared = EnvLoader()

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Load configuration (no-op, kept for compatibility).
    func load() {
        print("[EnvLoader] Using UserDefaults configuration")
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
