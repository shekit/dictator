import SwiftUI

/// Settings window with tabbed interface for configuring Dictator.
struct SettingsWindow: View {
    @ObservedObject var llmService: LLMService
    @State private var selectedTab: SettingsTab = .prompts

    enum SettingsTab: String, CaseIterable {
        case prompts = "Prompts"
        case dictionary = "Dictionary"
        case history = "History"
        case stats = "Stats"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .prompts: return "text.alignleft"
            case .dictionary: return "book.closed"
            case .history: return "clock.arrow.circlepath"
            case .stats: return "chart.bar"
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

                HistoryTabView()
                    .tag(SettingsTab.history)

                StatsTabView()
                    .tag(SettingsTab.stats)

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
    @ObservedObject var launchAtLogin = LaunchAtLoginService.shared
    @State private var apiKey: String = ""
    @State private var isEditingAPIKey = false

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

                // Launch at Login
                VStack(alignment: .leading, spacing: 8) {
                    Text("Startup")
                        .font(.headline)

                    Toggle("Launch at login", isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    ))
                    .toggleStyle(.switch)

                    Text("Automatically start Dictator when you log in")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // API Key Configuration
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Configuration")
                        .font(.headline)

                    if isEditingAPIKey {
                        VStack(alignment: .leading, spacing: 8) {
                            SecureField("Enter your OpenRouter API key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)

                            Text("Example: sk-or-v1-...")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack {
                                Button("Save") {
                                    saveAPIKey()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Cancel") {
                                    isEditingAPIKey = false
                                    loadAPIKey()
                                }
                                .buttonStyle(.bordered)

                                if UserDefaults.standard.string(forKey: "openRouterAPIKey") != nil {
                                    Button("Remove") {
                                        removeAPIKey()
                                    }
                                    .buttonStyle(.bordered)
                                    .foregroundColor(.red)
                                }
                            }
                        }
                    } else {
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

                            Spacer()

                            Button(UserDefaults.standard.string(forKey: "openRouterAPIKey") != nil ? "Edit" : "Add") {
                                isEditingAPIKey = true
                                loadAPIKey()
                            }
                            .buttonStyle(.bordered)
                        }

                        if UserDefaults.standard.string(forKey: "openRouterAPIKey") != nil {
                            Text("API key stored locally")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if let envPath = EnvLoader.shared.envFileLocation {
                            Text("Using API key from: \(envPath)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Add your API key to use cloud LLM processing")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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

    private func loadAPIKey() {
        apiKey = UserDefaults.standard.string(forKey: "openRouterAPIKey") ?? ""
    }

    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: "openRouterAPIKey")
            print("[Settings] API key saved")
        }
        isEditingAPIKey = false
    }

    private func removeAPIKey() {
        UserDefaults.standard.removeObject(forKey: "openRouterAPIKey")
        apiKey = ""
        isEditingAPIKey = false
        print("[Settings] API key removed")
    }
}

// MARK: - History Tab

struct HistoryTabView: View {
    @State private var entries: [TranscriptionLogger.LogEntry] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Transcription History")
                    .font(.headline)

                Spacer()

                Text("\(entries.count) recordings")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Refresh") {
                    loadEntries()
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // List of entries
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading history...")
                    Spacer()
                }
            } else if entries.isEmpty {
                VStack {
                    Spacer()
                    Text("No transcriptions yet")
                        .foregroundColor(.secondary)
                    Text("Start recording to see your history here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(entries, id: \.timestamp) { entry in
                    HistoryEntryRow(entry: entry)
                }
            }
        }
        .onAppear {
            loadEntries()
        }
    }

    private func loadEntries() {
        isLoading = true
        Task {
            let loaded = await TranscriptionLogger.shared.recentEntries(limit: 100)
            await MainActor.run {
                entries = loaded
                isLoading = false
            }
        }
    }
}

struct HistoryEntryRow: View {
    let entry: TranscriptionLogger.LogEntry

    private var formattedTimestamp: String {
        // Parse ISO 8601 timestamp and format it nicely
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: entry.timestamp) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return entry.timestamp
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Timestamp and metadata
            HStack {
                Text(formattedTimestamp)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(entry.wordCount) words")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("•")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(String(format: "%.0f WPM", entry.wpm))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("•")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(entry.mode)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Cleaned text (what was actually typed)
            Text(entry.cleanedText)
                .font(.body)
                .lineLimit(3)

            // Show raw text if different
            if entry.rawText != entry.cleanedText {
                Text("Raw: \(entry.rawText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Stats Tab

struct StatsTabView: View {
    @ObservedObject private var statsService = StatsService.shared

    private var weekStats: (words: Int, recordings: Int, averageWPM: Double) {
        statsService.weekStats()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Today's Stats
                VStack(alignment: .leading, spacing: 12) {
                    Text("Today")
                        .font(.title2.bold())

                    HStack(spacing: 40) {
                        StatBox(
                            title: "Words",
                            value: "\(statsService.todayStats.totalWords)",
                            icon: "text.word.spacing"
                        )

                        StatBox(
                            title: "Recordings",
                            value: "\(statsService.todayStats.recordingCount)",
                            icon: "mic.fill"
                        )

                        StatBox(
                            title: "Avg WPM",
                            value: String(format: "%.0f", statsService.todayStats.averageWPM),
                            icon: "speedometer"
                        )
                    }
                }

                Divider()

                // This Week Stats
                VStack(alignment: .leading, spacing: 12) {
                    Text("This Week (Last 7 Days)")
                        .font(.title2.bold())

                    HStack(spacing: 40) {
                        StatBox(
                            title: "Words",
                            value: "\(weekStats.words)",
                            icon: "text.word.spacing"
                        )

                        StatBox(
                            title: "Recordings",
                            value: "\(weekStats.recordings)",
                            icon: "mic.fill"
                        )

                        StatBox(
                            title: "Avg WPM",
                            value: String(format: "%.0f", weekStats.averageWPM),
                            icon: "speedometer"
                        )
                    }
                }

                Divider()

                // All-Time Stats
                VStack(alignment: .leading, spacing: 12) {
                    Text("All Time")
                        .font(.title2.bold())

                    HStack(spacing: 40) {
                        StatBox(
                            title: "Total Words",
                            value: "\(statsService.totalWordsAllTime)",
                            icon: "text.word.spacing"
                        )

                        StatBox(
                            title: "Total Recordings",
                            value: "\(statsService.totalRecordingsAllTime)",
                            icon: "mic.fill"
                        )

                        StatBox(
                            title: "Avg WPM",
                            value: String(format: "%.0f", statsService.averageWPMAllTime),
                            icon: "speedometer"
                        )
                    }
                }
            }
            .padding()
        }
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)

            Text(value)
                .font(.title.bold())

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 120)
    }
}
