import Foundation

/// Manages LLM-based text cleanup.
/// Handles prompt construction, settings persistence, and API coordination.
@MainActor
final class LLMService: ObservableObject {
    // MARK: - Singleton

    static let shared = LLMService()

    // MARK: - Types

    enum ProcessingMode: String, Codable, CaseIterable {
        case cloud = "cloud"
        case local = "local"
        case off = "off"

        var displayName: String {
            switch self {
            case .cloud: return "Cloud (OpenRouter)"
            case .local: return "Local (Ollama)"
            case .off: return "Off (Raw Text)"
            }
        }
    }

    struct DictionaryEntry: Codable, Identifiable, Equatable {
        let id: UUID
        var spoken: String    // What the user says
        var replacement: String  // What it should become

        init(spoken: String, replacement: String) {
            self.id = UUID()
            self.spoken = spoken
            self.replacement = replacement
        }
    }

    // MARK: - Published Settings

    @Published var processingMode: ProcessingMode = .off {
        didSet { saveSettings() }
    }

    @Published var selectedCloudModel: String = OpenRouterClient.defaultModel {
        didSet { saveSettings() }
    }

    @Published var selectedLocalModel: String = "" {
        didSet { saveSettings() }
    }

    @Published var advancedPromptEnabled: Bool = true {
        didSet { saveSettings() }
    }

    @Published var dictionaryEntries: [DictionaryEntry] = [] {
        didSet { saveSettings() }
    }

    @Published var customMainPrompt: String? = nil {
        didSet { saveSettings() }
    }

    /// Cached list of available Ollama models
    @Published var availableLocalModels: [OllamaClient.ModelInfo] = []

    /// Whether Ollama is currently available
    @Published var isOllamaAvailable: Bool = false

    // MARK: - Properties

    private let openRouterClient = OpenRouterClient()
    private let ollamaClient = OllamaClient()
    private let defaults = UserDefaults.standard

    // UserDefaults keys
    private let kProcessingMode = "llm.processingMode"
    private let kSelectedCloudModel = "llm.selectedCloudModel"
    private let kSelectedLocalModel = "llm.selectedLocalModel"
    private let kAdvancedPromptEnabled = "llm.advancedPromptEnabled"
    private let kDictionaryEntries = "llm.dictionaryEntries"
    private let kCustomMainPrompt = "llm.customMainPrompt"

    // MARK: - Default Prompts

    /// Main prompt: removes fillers, adds punctuation
    static let defaultMainPrompt = """
    Clean up this dictated text. Your task:
    1. Remove filler words (um, uh, like, you know, so, basically, actually, I mean, well)
    2. Add proper punctuation (periods, commas, question marks)
    3. Fix obvious grammar mistakes
    4. Capitalize appropriately (sentences, proper nouns)
    5. Convert spelled-out numbers to digits (thirty-three → 33, two thousand → 2000)
    6. Keep the original meaning and tone intact
    7. Do NOT add content or change what was said

    Return ONLY the cleaned text, nothing else. No explanations, no quotes, no prefixes.
    """

    /// Advanced prompt: handles backtracking/corrections
    static let advancedPrompt = """
    ADDITIONAL RULES for handling speech corrections:
    - When the speaker backtracks ("wait no", "I mean", "actually", "sorry"), remove the corrected part and keep only the final version
    - Example: "I want to go to the wait no I want to stay home" → "I want to stay home."
    - Example: "Send it to John actually send it to Jane" → "Send it to Jane."
    - Detect and handle stuttering: "I I I want" → "I want"
    """

    // MARK: - Initialization

    private init() {
        loadSettings()
        // Check Ollama availability on init
        Task {
            await refreshOllamaStatus()
        }
    }

    // MARK: - Public Methods

    /// Refresh Ollama availability status and model list.
    func refreshOllamaStatus() async {
        let available = await ollamaClient.checkHealth()
        await MainActor.run {
            self.isOllamaAvailable = available
        }

        if available {
            do {
                let models = try await ollamaClient.listModels()
                await MainActor.run {
                    self.availableLocalModels = models
                    print("[LLMService] Found \(models.count) Ollama models: \(models.map { $0.name }.joined(separator: ", "))")

                    // Auto-select first model if none selected or selected model doesn't exist
                    if !models.isEmpty {
                        let selectedModelExists = models.contains { $0.name == self.selectedLocalModel }
                        if !selectedModelExists {
                            self.selectedLocalModel = models[0].name
                            print("[LLMService] Auto-selected model: \(self.selectedLocalModel)")
                        }
                    }
                }
            } catch {
                print("[LLMService] Failed to list Ollama models: \(error.localizedDescription)")
            }
        } else {
            await MainActor.run {
                self.availableLocalModels = []
            }
        }
    }

    /// Process transcription through LLM for cleanup.
    /// Returns the original text if processing is disabled or fails.
    func processTranscription(_ rawText: String) async -> (text: String, wasProcessed: Bool) {
        // If processing is off, return raw text
        guard processingMode != .off else {
            print("[LLMService] Processing disabled, returning raw text")
            return (rawText, false)
        }

        // Skip empty or very short text
        guard rawText.count >= 3 else {
            return (rawText, false)
        }

        // For cloud mode, use OpenRouter
        if processingMode == .cloud {
            do {
                let cleanedText = try await processWithOpenRouter(rawText)
                return (cleanedText, true)
            } catch {
                print("[LLMService] OpenRouter processing failed: \(error.localizedDescription)")
                // Fall back to raw text on error
                return (rawText, false)
            }
        }

        // For local mode, use Ollama
        if processingMode == .local {
            do {
                let cleanedText = try await processWithOllama(rawText)
                return (cleanedText, true)
            } catch {
                print("[LLMService] Ollama processing failed: \(error.localizedDescription)")
                // Fall back to raw text on error
                return (rawText, false)
            }
        }

        return (rawText, false)
    }

    /// Check if cloud processing is available.
    var isCloudAvailable: Bool {
        EnvLoader.shared.hasOpenRouterKey
    }

    /// Get descriptive status of current mode.
    var modeStatusDescription: String {
        switch processingMode {
        case .cloud:
            if isCloudAvailable {
                return "Cloud: \(selectedCloudModelName)"
            } else {
                return "Cloud: No API Key"
            }
        case .local:
            if isOllamaAvailable {
                return "Local: \(selectedLocalModelName)"
            } else {
                return "Local: Ollama Not Running"
            }
        case .off:
            return "LLM: Off"
        }
    }

    /// Get short name for current cloud model.
    var selectedCloudModelName: String {
        if let model = OpenRouterClient.availableModels.first(where: { $0.id == selectedCloudModel }) {
            // Extract just the model name part
            let parts = model.name.components(separatedBy: " - ")
            return parts.first ?? model.name
        }
        return selectedCloudModel.components(separatedBy: "/").last ?? selectedCloudModel
    }

    /// Get short name for current local model.
    var selectedLocalModelName: String {
        // Remove :latest suffix if present
        if selectedLocalModel.hasSuffix(":latest") {
            return String(selectedLocalModel.dropLast(7))
        }
        return selectedLocalModel
    }

    // MARK: - Dictionary Management

    func addDictionaryEntry(spoken: String, replacement: String) {
        let entry = DictionaryEntry(spoken: spoken, replacement: replacement)
        dictionaryEntries.append(entry)
    }

    func removeDictionaryEntry(id: UUID) {
        dictionaryEntries.removeAll { $0.id == id }
    }

    func updateDictionaryEntry(id: UUID, spoken: String, replacement: String) {
        if let index = dictionaryEntries.firstIndex(where: { $0.id == id }) {
            dictionaryEntries[index].spoken = spoken
            dictionaryEntries[index].replacement = replacement
        }
    }

    // MARK: - Private Methods

    private func processWithOpenRouter(_ rawText: String) async throws -> String {
        let systemPrompt = buildSystemPrompt()

        let messages: [OpenRouterClient.ChatMessage] = [
            OpenRouterClient.ChatMessage(role: "system", content: systemPrompt),
            OpenRouterClient.ChatMessage(role: "user", content: rawText)
        ]

        print("[LLMService] Sending to OpenRouter (model: \(selectedCloudModel))")

        let response = try await openRouterClient.complete(
            messages: messages,
            model: selectedCloudModel,
            temperature: 0.3,
            maxTokens: 500
        )

        print("[LLMService] OpenRouter response: '\(response.content)'")

        if let usage = response.usage {
            print("[LLMService] Tokens used: \(usage.promptTokens) prompt, \(usage.completionTokens) completion")
        }

        return response.content
    }

    private func processWithOllama(_ rawText: String) async throws -> String {
        let systemPrompt = buildSystemPrompt()

        // Add explicit task prefix to help smaller models understand the task
        let formattedPrompt = "Clean this text: \(rawText)"

        print("[LLMService] Sending to Ollama (model: \(selectedLocalModel))")

        let response = try await ollamaClient.generate(
            prompt: formattedPrompt,
            systemPrompt: systemPrompt,
            model: selectedLocalModel
        )

        print("[LLMService] Ollama response: '\(response.response)'")

        if let duration = response.totalDuration {
            let durationMs = Double(duration) / 1_000_000
            print("[LLMService] Processing time: \(String(format: "%.0f", durationMs))ms")
        }

        return response.response
    }

    private func buildSystemPrompt() -> String {
        var prompt = customMainPrompt ?? Self.defaultMainPrompt

        // Add advanced prompt if enabled
        if advancedPromptEnabled {
            prompt += "\n\n" + Self.advancedPrompt
        }

        // Add dictionary entries if any
        if !dictionaryEntries.isEmpty {
            prompt += "\n\nCUSTOM DICTIONARY - Replace these terms:\n"
            for entry in dictionaryEntries {
                prompt += "- \"\(entry.spoken)\" → \"\(entry.replacement)\"\n"
            }
        }

        return prompt
    }

    // MARK: - Persistence

    private func loadSettings() {
        // Processing mode
        if let modeString = defaults.string(forKey: kProcessingMode),
           let mode = ProcessingMode(rawValue: modeString) {
            processingMode = mode
        } else {
            // First run: default to cloud if API key is set, otherwise raw
            processingMode = EnvLoader.shared.hasOpenRouterKey ? .cloud : .off
        }

        // Cloud model
        if let model = defaults.string(forKey: kSelectedCloudModel) {
            selectedCloudModel = model
        }

        // Local model
        if let model = defaults.string(forKey: kSelectedLocalModel) {
            selectedLocalModel = model
        }

        // Advanced prompt toggle
        if defaults.object(forKey: kAdvancedPromptEnabled) != nil {
            advancedPromptEnabled = defaults.bool(forKey: kAdvancedPromptEnabled)
        }

        // Dictionary entries
        if let data = defaults.data(forKey: kDictionaryEntries),
           let entries = try? JSONDecoder().decode([DictionaryEntry].self, from: data) {
            dictionaryEntries = entries
        }

        // Custom main prompt
        customMainPrompt = defaults.string(forKey: kCustomMainPrompt)

        print("[LLMService] Settings loaded: mode=\(processingMode.rawValue), cloudModel=\(selectedCloudModel), localModel=\(selectedLocalModel), advancedPrompt=\(advancedPromptEnabled), dictionary=\(dictionaryEntries.count) entries")
    }

    private func saveSettings() {
        defaults.set(processingMode.rawValue, forKey: kProcessingMode)
        defaults.set(selectedCloudModel, forKey: kSelectedCloudModel)
        defaults.set(selectedLocalModel, forKey: kSelectedLocalModel)
        defaults.set(advancedPromptEnabled, forKey: kAdvancedPromptEnabled)
        defaults.set(customMainPrompt, forKey: kCustomMainPrompt)

        if let data = try? JSONEncoder().encode(dictionaryEntries) {
            defaults.set(data, forKey: kDictionaryEntries)
        }
    }
}
