import SwiftUI

/// Settings window with tabbed interface for configuring Dictator.
struct SettingsWindow: View {
    @ObservedObject var llmService: LLMService
    @State private var selectedTab: SettingsTab = .prompts

    enum SettingsTab: String, CaseIterable {
        case prompts = "Prompts"
        case dictionary = "Dictionary"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .prompts: return "text.alignleft"
            case .dictionary: return "book.closed"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("Settings Tab", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Tab content
            TabView(selection: $selectedTab) {
                PromptsTabView(llmService: llmService)
                    .tag(SettingsTab.prompts)

                DictionaryTabView(llmService: llmService)
                    .tag(SettingsTab.dictionary)

                SettingsTabView(llmService: llmService)
                    .tag(SettingsTab.settings)
            }
            .tabViewStyle(.automatic)
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - Prompts Tab

struct PromptsTabView: View {
    @ObservedObject var llmService: LLMService
    @State private var editedMainPrompt: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Main Prompt Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Main Prompt")
                        .font(.headline)

                    Text("This prompt removes filler words and adds punctuation.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: $editedMainPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 180)
                        .border(Color.gray.opacity(0.3), width: 1)
                        .onChange(of: editedMainPrompt) {
                            llmService.customMainPrompt = editedMainPrompt
                        }

                    HStack {
                        Button("Reset to Default") {
                            editedMainPrompt = LLMService.defaultMainPrompt
                            llmService.customMainPrompt = nil
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                }

                Divider()

                // Advanced Prompt Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Advanced Prompt")
                            .font(.headline)

                        Spacer()

                        Toggle("Enabled", isOn: $llmService.advancedPromptEnabled)
                    }

                    Text("Handles backtracking and corrections (e.g., 'wait no', 'I mean').")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: .constant(LLMService.advancedPrompt))
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 120)
                        .border(Color.gray.opacity(0.3), width: 1)
                        .disabled(true)
                        .opacity(llmService.advancedPromptEnabled ? 1.0 : 0.5)
                }
            }
            .padding()
        }
        .onAppear {
            editedMainPrompt = llmService.customMainPrompt ?? LLMService.defaultMainPrompt
        }
    }
}

// MARK: - Dictionary Tab

struct DictionaryTabView: View {
    @ObservedObject var llmService: LLMService
    @State private var newSpoken: String = ""
    @State private var newReplacement: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Add new entry form
            VStack(alignment: .leading, spacing: 8) {
                Text("Add Dictionary Entry")
                    .font(.headline)

                Text("Replace spoken phrases with specific text.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Spoken").font(.caption)
                        TextField("e.g., ant row pic", text: $newSpoken)
                            .textFieldStyle(.roundedBorder)
                    }

                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Replacement").font(.caption)
                        TextField("e.g., Anthropic", text: $newReplacement)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button("Add") {
                        guard !newSpoken.isEmpty && !newReplacement.isEmpty else { return }
                        llmService.addDictionaryEntry(spoken: newSpoken, replacement: newReplacement)
                        newSpoken = ""
                        newReplacement = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newSpoken.isEmpty || newReplacement.isEmpty)
                }
            }
            .padding()

            Divider()

            // List of entries
            if llmService.dictionaryEntries.isEmpty {
                VStack {
                    Spacer()
                    Text("No dictionary entries yet")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(llmService.dictionaryEntries) { entry in
                        DictionaryEntryRow(entry: entry, llmService: llmService)
                    }
                }
            }
        }
    }
}

struct DictionaryEntryRow: View {
    let entry: LLMService.DictionaryEntry
    @ObservedObject var llmService: LLMService
    @State private var isEditing: Bool = false
    @State private var editedSpoken: String = ""
    @State private var editedReplacement: String = ""

    var body: some View {
        HStack {
            if isEditing {
                TextField("Spoken", text: $editedSpoken)
                    .textFieldStyle(.roundedBorder)

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)

                TextField("Replacement", text: $editedReplacement)
                    .textFieldStyle(.roundedBorder)

                Button("Save") {
                    llmService.updateDictionaryEntry(id: entry.id, spoken: editedSpoken, replacement: editedReplacement)
                    isEditing = false
                }
                .buttonStyle(.borderedProminent)

                Button("Cancel") {
                    isEditing = false
                }
                .buttonStyle(.bordered)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.spoken)
                            .font(.body)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(entry.replacement)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button("Edit") {
                    editedSpoken = entry.spoken
                    editedReplacement = entry.replacement
                    isEditing = true
                }
                .buttonStyle(.bordered)

                Button("Delete") {
                    llmService.removeDictionaryEntry(id: entry.id)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings Tab

struct SettingsTabView: View {
    @ObservedObject var llmService: LLMService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hotkey Configuration
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hotkey")
                        .font(.headline)

                    Text("Current hotkey: fn (hold to record)")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Text("Note: Hotkey configuration is currently fixed to the fn key.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // API Key Status
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Configuration")
                        .font(.headline)

                    HStack {
                        Text("OpenRouter API Key:")
                            .font(.body)

                        if EnvLoader.shared.hasOpenRouterKey {
                            Text("✓ Configured")
                                .foregroundColor(.green)
                                .font(.body.bold())
                        } else {
                            Text("✗ Not configured")
                                .foregroundColor(.red)
                                .font(.body.bold())
                        }
                    }

                    if let envPath = EnvLoader.shared.envFileLocation {
                        Text("Configuration file: \(envPath)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Add OPENROUTER_API_KEY to .env file in:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("~/.env or ~/Documents/Dictator/.env")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Processing Mode
                VStack(alignment: .leading, spacing: 8) {
                    Text("Processing Mode")
                        .font(.headline)

                    Picker("Mode", selection: $llmService.processingMode) {
                        ForEach(LLMService.ProcessingMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(llmService.modeStatusDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Cloud Model Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cloud Model")
                        .font(.headline)

                    Picker("Cloud Model", selection: $llmService.selectedCloudModel) {
                        ForEach(OpenRouterClient.availableModels, id: \.id) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    .disabled(llmService.processingMode != .cloud)

                    if llmService.processingMode != .cloud {
                        Text("Available only in Cloud mode")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Local Model Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Local Model (Ollama)")
                        .font(.headline)

                    if llmService.availableLocalModels.isEmpty {
                        Text("No Ollama models found")
                            .foregroundColor(.secondary)

                        if !llmService.isOllamaAvailable {
                            Text("Start Ollama with 'ollama serve' in Terminal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Picker("Local Model", selection: $llmService.selectedLocalModel) {
                            ForEach(llmService.availableLocalModels, id: \.name) { model in
                                Text("\(model.displayName) (\(model.sizeDescription))").tag(model.name)
                            }
                        }
                        .disabled(llmService.processingMode != .local)

                        if llmService.processingMode != .local {
                            Text("Available only in Local mode")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button("Refresh Ollama Models") {
                        Task {
                            await llmService.refreshOllamaStatus()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }
}
