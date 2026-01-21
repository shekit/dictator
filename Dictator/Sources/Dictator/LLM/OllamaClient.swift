import Foundation

/// HTTP client for Ollama API (local LLM).
/// Handles health checking, model listing, and text generation.
actor OllamaClient {
    // MARK: - Types

    enum OllamaError: LocalizedError {
        case notRunning
        case invalidResponse
        case httpError(statusCode: Int, message: String)
        case networkError(Error)
        case decodingError(Error)
        case emptyResponse
        case noModelsInstalled
        case modelNotFound(String)

        var errorDescription: String? {
            switch self {
            case .notRunning:
                return "Ollama is not running. Start it with 'ollama serve' in Terminal."
            case .invalidResponse:
                return "Invalid response from Ollama"
            case .httpError(let code, let message):
                return "Ollama error (\(code)): \(message)"
            case .networkError(let error):
                return "Failed to connect to Ollama: \(error.localizedDescription)"
            case .decodingError(let error):
                return "Failed to parse Ollama response: \(error.localizedDescription)"
            case .emptyResponse:
                return "Empty response from Ollama"
            case .noModelsInstalled:
                return "No Ollama models installed. Run 'ollama pull llama3.2' in Terminal."
            case .modelNotFound(let model):
                return "Model '\(model)' not found. Run 'ollama pull \(model)' to install it."
            }
        }
    }

    struct GenerateResponse {
        let response: String
        let model: String
        let totalDuration: Int64?  // nanoseconds
    }

    struct ModelInfo: Equatable {
        let name: String
        let size: Int64  // bytes
        let modifiedAt: Date?

        var sizeDescription: String {
            let gb = Double(size) / 1_000_000_000
            if gb >= 1 {
                return String(format: "%.1fGB", gb)
            }
            let mb = Double(size) / 1_000_000
            return String(format: "%.0fMB", mb)
        }

        var displayName: String {
            // Extract base name without tag if it's :latest
            if name.hasSuffix(":latest") {
                return String(name.dropLast(7))
            }
            return name
        }
    }

    // MARK: - Constants

    private static let defaultHost = "http://localhost:11434"
    private static let healthEndpoint = "/api/tags"  // List models = health check
    private static let generateEndpoint = "/api/generate"

    static let defaultModel = "llama3.2:3b"

    // MARK: - Properties

    private var baseURL: String

    // MARK: - Initialization

    init(host: String? = nil) {
        self.baseURL = host ?? Self.defaultHost
    }

    // MARK: - Public Methods

    /// Check if Ollama is running and accessible.
    func checkHealth() async -> Bool {
        do {
            _ = try await listModels()
            print("[OllamaClient] Ollama available at \(baseURL)")
            return true
        } catch {
            print("[OllamaClient] Ollama not available: \(error.localizedDescription)")
            return false
        }
    }

    /// List installed Ollama models.
    func listModels() async throws -> [ModelInfo] {
        let url = URL(string: baseURL + Self.healthEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCannotConnectToHost ||
               nsError.code == NSURLErrorNetworkConnectionLost ||
               nsError.code == NSURLErrorTimedOut {
                throw OllamaError.notRunning
            }
            throw OllamaError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw OllamaError.httpError(statusCode: httpResponse.statusCode, message: "Failed to list models")
        }

        return try parseModelsResponse(data)
    }

    /// Generate text completion using Ollama.
    func generate(
        prompt: String,
        systemPrompt: String? = nil,
        model: String = OllamaClient.defaultModel
    ) async throws -> GenerateResponse {
        // First check if Ollama is running
        let models = try await listModels()
        if models.isEmpty {
            throw OllamaError.noModelsInstalled
        }

        // Check if requested model is available
        let modelExists = models.contains { $0.name == model || $0.name.hasPrefix(model.split(separator: ":").first.map(String.init) ?? model) }
        if !modelExists {
            throw OllamaError.modelNotFound(model)
        }

        // Build request
        let url = URL(string: baseURL + Self.generateEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60  // LLM can take a while

        var body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false
        ]

        if let system = systemPrompt {
            body["system"] = system
        }

        // Add generation options for faster response
        body["options"] = [
            "temperature": 0.3,
            "num_predict": 500
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw OllamaError.invalidResponse
        }
        request.httpBody = jsonData

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCannotConnectToHost {
                throw OllamaError.notRunning
            }
            throw OllamaError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OllamaError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        return try parseGenerateResponse(data)
    }

    // MARK: - Private Methods

    private func parseModelsResponse(_ data: Data) throws -> [ModelInfo] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw OllamaError.decodingError(NSError(domain: "Ollama", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid models response"]))
        }

        return models.compactMap { modelDict -> ModelInfo? in
            guard let name = modelDict["name"] as? String else { return nil }
            let size = modelDict["size"] as? Int64 ?? 0

            var modifiedAt: Date? = nil
            if let modifiedString = modelDict["modified_at"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                modifiedAt = formatter.date(from: modifiedString)
            }

            return ModelInfo(name: name, size: size, modifiedAt: modifiedAt)
        }
    }

    private func parseGenerateResponse(_ data: Data) throws -> GenerateResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OllamaError.decodingError(NSError(domain: "Ollama", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"]))
        }

        guard let response = json["response"] as? String else {
            throw OllamaError.emptyResponse
        }

        let model = json["model"] as? String ?? "unknown"
        let totalDuration = json["total_duration"] as? Int64

        return GenerateResponse(
            response: response.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model,
            totalDuration: totalDuration
        )
    }
}
