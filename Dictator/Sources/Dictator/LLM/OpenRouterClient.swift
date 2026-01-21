import Foundation

/// HTTP client for OpenRouter API.
/// Handles authentication, request building, and response parsing.
actor OpenRouterClient {
    // MARK: - Types

    enum OpenRouterError: LocalizedError {
        case noAPIKey
        case invalidResponse
        case httpError(statusCode: Int, message: String)
        case networkError(Error)
        case decodingError(Error)
        case emptyResponse
        case rateLimited(retryAfter: Int?)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "OpenRouter API key not configured. Add OPENROUTER_API_KEY to .env file."
            case .invalidResponse:
                return "Invalid response from OpenRouter API"
            case .httpError(let code, let message):
                return "OpenRouter API error (\(code)): \(message)"
            case .networkError(let error):
                if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                    return "No internet connection. Check your network and try again."
                }
                return "Network error: \(error.localizedDescription)"
            case .decodingError(let error):
                return "Failed to parse response: \(error.localizedDescription)"
            case .emptyResponse:
                return "Empty response from OpenRouter API"
            case .rateLimited(let retryAfter):
                if let seconds = retryAfter {
                    return "Rate limited. Try again in \(seconds) seconds."
                }
                return "Rate limited. Please try again later."
            }
        }

        var isRetryable: Bool {
            switch self {
            case .networkError, .rateLimited:
                return true
            case .httpError(let code, _):
                return code >= 500 || code == 429
            default:
                return false
            }
        }
    }

    struct ChatMessage {
        let role: String  // "system", "user", "assistant"
        let content: String
    }

    struct CompletionResponse {
        let content: String
        let model: String
        let usage: Usage?

        struct Usage {
            let promptTokens: Int
            let completionTokens: Int
            let totalTokens: Int
        }
    }

    // MARK: - Constants

    private static let baseURL = "https://openrouter.ai/api/v1/chat/completions"
    private static let maxRetries = 3
    private static let retryDelayMs = 200

    // MARK: - Available Models

    static let availableModels: [(id: String, name: String)] = [
        ("meta-llama/llama-3.3-70b-instruct", "Llama 3.3 70B"),
        ("anthropic/claude-3.5-haiku", "Claude 3.5 Haiku"),
        ("openai/gpt-4o-mini", "GPT-4o Mini"),
    ]

    static let defaultModel = "meta-llama/llama-3.3-70b-instruct"

    // MARK: - Public Methods

    /// Send a chat completion request to OpenRouter.
    func complete(
        messages: [ChatMessage],
        model: String = OpenRouterClient.defaultModel,
        temperature: Double = 0.3,
        maxTokens: Int = 500
    ) async throws -> CompletionResponse {
        guard let apiKey = await getAPIKey(), !apiKey.isEmpty else {
            throw OpenRouterError.noAPIKey
        }

        var lastError: Error?

        for attempt in 1...Self.maxRetries {
            do {
                return try await makeRequest(
                    messages: messages,
                    model: model,
                    temperature: temperature,
                    maxTokens: maxTokens,
                    apiKey: apiKey
                )
            } catch let error as OpenRouterError where error.isRetryable && attempt < Self.maxRetries {
                lastError = error
                let delayMs = Self.retryDelayMs * (1 << (attempt - 1))  // Exponential backoff
                try? await Task.sleep(for: .milliseconds(delayMs))
                print("[OpenRouterClient] Retry \(attempt)/\(Self.maxRetries) after error: \(error.localizedDescription)")
            } catch {
                throw error
            }
        }

        throw lastError ?? OpenRouterError.invalidResponse
    }

    // MARK: - Private Methods

    @MainActor
    private func getAPIKey() -> String? {
        EnvLoader.shared.openRouterAPIKey
    }

    private func makeRequest(
        messages: [ChatMessage],
        model: String,
        temperature: Double,
        maxTokens: Int,
        apiKey: String
    ) async throws -> CompletionResponse {
        // Build request body
        let messagesArray = messages.map { msg in
            ["role": msg.role, "content": msg.content]
        }

        let body: [String: Any] = [
            "model": model,
            "messages": messagesArray,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw OpenRouterError.invalidResponse
        }

        // Build request
        guard let url = URL(string: Self.baseURL) else {
            throw OpenRouterError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Dictator macOS App", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Dictator", forHTTPHeaderField: "X-Title")
        request.httpBody = jsonData
        request.timeoutInterval = 45

        // Make request
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OpenRouterError.networkError(error)
        }

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Int($0) }
            throw OpenRouterError.rateLimited(retryAfter: retryAfter)
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = parseErrorMessage(from: data) ?? "Unknown error"
            throw OpenRouterError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        // Parse response
        return try parseResponse(data)
    }

    private func parseResponse(_ data: Data) throws -> CompletionResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenRouterError.decodingError(NSError(domain: "OpenRouter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"]))
        }

        // Extract content from choices
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            // Check for error in response
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw OpenRouterError.httpError(statusCode: 400, message: message)
            }
            throw OpenRouterError.emptyResponse
        }

        // Extract model used
        let model = json["model"] as? String ?? "unknown"

        // Extract usage stats
        var usage: CompletionResponse.Usage? = nil
        if let usageDict = json["usage"] as? [String: Any] {
            usage = CompletionResponse.Usage(
                promptTokens: usageDict["prompt_tokens"] as? Int ?? 0,
                completionTokens: usageDict["completion_tokens"] as? Int ?? 0,
                totalTokens: usageDict["total_tokens"] as? Int ?? 0
            )
        }

        return CompletionResponse(
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model,
            usage: usage
        )
    }

    private func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }

        if let error = json["error"] as? [String: Any] {
            return error["message"] as? String
        }

        return json["message"] as? String
    }
}
