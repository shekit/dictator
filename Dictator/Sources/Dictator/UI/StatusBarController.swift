import AppKit
import Combine

@MainActor
final class StatusBarController {
    // MARK: - Types

    enum IconState {
        case idle
        case recording
        case transcribing
        case processing
        case injecting
        case error
    }

    // MARK: - Properties

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let quitItem: NSMenuItem
    private let statusMenuItem = NSMenuItem()
    private let llmStatusMenuItem = NSMenuItem()
    private var modeSubmenu = NSMenu()
    private var cloudModelSubmenu = NSMenu()
    private var localModelSubmenu = NSMenu()
    private let quitAction: () -> Void

    private var recordingService: RecordingService?
    private var llmService: LLMService?
    private var cancellables = Set<AnyCancellable>()

    private let normalIcon = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Dictator")
    private let recordingIcon = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "Recording")
    private let transcribingIcon = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Transcribing")
    private let processingIcon = NSImage(systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: "Processing")
    private let injectingIcon = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "Injecting")
    private let errorIcon = NSImage(systemSymbolName: "mic.slash.fill", accessibilityDescription: "Error")

    // MARK: - Initialization

    init(quitAction: @escaping () -> Void) {
        self.quitAction = quitAction
        self.quitItem = NSMenuItem(title: "Quit Dictator", action: nil, keyEquivalent: "q")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        configureButton()
        configureMenu()
    }

    // MARK: - Public Methods

    /// Set the recording service for state observation.
    func setRecordingService(_ service: RecordingService) {
        self.recordingService = service

        // Observe state changes
        service.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleStateChange(state)
            }
            .store(in: &cancellables)
    }

    /// Set the LLM service for settings observation.
    func setLLMService(_ service: LLMService) {
        self.llmService = service

        // Observe processing mode changes
        service.$processingMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLLMMenuItems()
            }
            .store(in: &cancellables)

        // Observe cloud model changes
        service.$selectedCloudModel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLLMMenuItems()
            }
            .store(in: &cancellables)

        // Observe local model changes
        service.$selectedLocalModel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLLMMenuItems()
            }
            .store(in: &cancellables)

        // Observe Ollama availability changes
        service.$isOllamaAvailable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLLMMenuItems()
            }
            .store(in: &cancellables)

        // Observe available local models changes
        service.$availableLocalModels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildLocalModelSubmenu()
            }
            .store(in: &cancellables)

        // Initial update
        updateLLMMenuItems()
    }

    /// Update the menu bar icon state.
    func setIconState(_ state: IconState) {
        guard let button = statusItem.button else { return }

        let icon: NSImage?
        switch state {
        case .idle:
            icon = normalIcon
            button.appearsDisabled = false
        case .recording:
            icon = recordingIcon
            button.appearsDisabled = false
        case .transcribing:
            icon = transcribingIcon
            button.appearsDisabled = false
        case .processing:
            icon = processingIcon
            button.appearsDisabled = false
        case .injecting:
            icon = injectingIcon
            button.appearsDisabled = false
        case .error:
            icon = errorIcon
            button.appearsDisabled = true
        }

        icon?.isTemplate = true
        button.image = icon
    }

    // MARK: - Private Methods

    private func configureButton() {
        guard let button = statusItem.button else { return }

        normalIcon?.isTemplate = true
        button.image = normalIcon
    }

    private func configureMenu() {
        quitItem.target = self
        quitItem.action = #selector(handleQuit)

        // Status display item (disabled, just for info)
        statusMenuItem.title = "Status: Ready"
        statusMenuItem.isEnabled = false

        // LLM status display (disabled, just for info)
        llmStatusMenuItem.title = "LLM: Loading..."
        llmStatusMenuItem.isEnabled = false

        // Mode selection submenu (Cloud/Local/Off)
        let modeMenuItem = NSMenuItem(title: "Processing Mode", action: nil, keyEquivalent: "")
        buildModeSubmenu()
        modeMenuItem.submenu = modeSubmenu

        // Cloud model selection submenu
        let cloudModelMenuItem = NSMenuItem(title: "Cloud Model", action: nil, keyEquivalent: "")
        buildCloudModelSubmenu()
        cloudModelMenuItem.submenu = cloudModelSubmenu

        // Local model selection submenu
        let localModelMenuItem = NSMenuItem(title: "Local Model", action: nil, keyEquivalent: "")
        buildLocalModelSubmenu()
        localModelMenuItem.submenu = localModelSubmenu

        menu.items = [
            statusMenuItem,
            NSMenuItem.separator(),
            llmStatusMenuItem,
            modeMenuItem,
            cloudModelMenuItem,
            localModelMenuItem,
            NSMenuItem.separator(),
            quitItem
        ]
        statusItem.menu = menu
    }

    private func buildModeSubmenu() {
        modeSubmenu.removeAllItems()

        for mode in LLMService.ProcessingMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(handleModeSelection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            modeSubmenu.addItem(item)
        }
    }

    private func buildCloudModelSubmenu() {
        cloudModelSubmenu.removeAllItems()

        for model in OpenRouterClient.availableModels {
            let item = NSMenuItem(title: model.name, action: #selector(handleCloudModelSelection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model.id
            cloudModelSubmenu.addItem(item)
        }
    }

    private func buildLocalModelSubmenu() {
        localModelSubmenu.removeAllItems()
        rebuildLocalModelSubmenu()
    }

    private func rebuildLocalModelSubmenu() {
        localModelSubmenu.removeAllItems()

        guard let service = llmService else { return }

        if service.availableLocalModels.isEmpty {
            let noModelsItem = NSMenuItem(title: "No models available", action: nil, keyEquivalent: "")
            noModelsItem.isEnabled = false
            localModelSubmenu.addItem(noModelsItem)

            if !service.isOllamaAvailable {
                let hintItem = NSMenuItem(title: "Ollama not running", action: nil, keyEquivalent: "")
                hintItem.isEnabled = false
                localModelSubmenu.addItem(hintItem)
            }
        } else {
            for model in service.availableLocalModels {
                let title = "\(model.displayName) (\(model.sizeDescription))"
                let item = NSMenuItem(title: title, action: #selector(handleLocalModelSelection(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = model.name
                localModelSubmenu.addItem(item)
            }
        }
    }

    private func updateLLMMenuItems() {
        guard let service = llmService else { return }

        // Update status display with offline indicator
        var statusText = "LLM: \(service.modeStatusDescription)"
        if service.processingMode == .local && service.isOllamaAvailable {
            statusText += " [Offline]"
        }
        llmStatusMenuItem.title = statusText

        // Update mode checkmarks
        for item in modeSubmenu.items {
            if let modeRaw = item.representedObject as? String {
                item.state = modeRaw == service.processingMode.rawValue ? .on : .off
            }
        }

        // Update cloud model checkmarks and enable state
        let enableCloudModels = service.processingMode == .cloud
        for item in cloudModelSubmenu.items {
            if let modelId = item.representedObject as? String {
                item.state = modelId == service.selectedCloudModel ? .on : .off
            }
            item.isEnabled = enableCloudModels
        }

        // Update local model checkmarks and enable state
        let enableLocalModels = service.processingMode == .local
        for item in localModelSubmenu.items {
            if let modelName = item.representedObject as? String {
                item.state = modelName == service.selectedLocalModel ? .on : .off
            }
            // Only enable if we're in local mode AND the item has a model (not the placeholder)
            if item.representedObject != nil {
                item.isEnabled = enableLocalModels
            }
        }
    }

    @objc private func handleModeSelection(_ sender: NSMenuItem) {
        guard let service = llmService,
              let modeRaw = sender.representedObject as? String,
              let mode = LLMService.ProcessingMode(rawValue: modeRaw) else { return }

        // If switching to cloud mode, check for API key
        if mode == .cloud && !EnvLoader.shared.hasOpenRouterKey {
            let alert = NSAlert()
            alert.messageText = "OpenRouter API Key Required"
            alert.informativeText = "To use Cloud mode, add OPENROUTER_API_KEY to your .env file.\n\nExpected location: \(EnvLoader.shared.envFileLocation ?? "~/.env or ~/Documents/Dictator/.env")"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // If switching to local mode, check Ollama and refresh
        if mode == .local {
            Task {
                await service.refreshOllamaStatus()
                if !service.isOllamaAvailable {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "Ollama Not Running"
                        alert.informativeText = "Ollama is not running. Start it with 'ollama serve' in Terminal, or install from ollama.ai"
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
        }

        service.processingMode = mode
        print("[StatusBarController] Mode changed to: \(mode.rawValue)")
    }

    @objc private func handleCloudModelSelection(_ sender: NSMenuItem) {
        guard let service = llmService,
              let modelId = sender.representedObject as? String else { return }

        service.selectedCloudModel = modelId
        print("[StatusBarController] Cloud model changed to: \(modelId)")
    }

    @objc private func handleLocalModelSelection(_ sender: NSMenuItem) {
        guard let service = llmService,
              let modelName = sender.representedObject as? String else { return }

        service.selectedLocalModel = modelName
        print("[StatusBarController] Local model changed to: \(modelName)")
    }

    private func handleStateChange(_ state: RecordingService.State) {
        switch state {
        case .idle:
            setIconState(.idle)
            statusMenuItem.title = "Status: Ready"
        case .recording:
            setIconState(.recording)
            statusMenuItem.title = "Status: Recording..."
        case .transcribing:
            setIconState(.transcribing)
            statusMenuItem.title = "Status: Transcribing..."
        case .processing:
            setIconState(.processing)
            statusMenuItem.title = "Status: Processing..."
        case .injecting:
            setIconState(.injecting)
            statusMenuItem.title = "Status: Injecting text..."
        case .error(let message):
            setIconState(.error)
            statusMenuItem.title = "Error: \(message)"
        }
    }

    @objc private func handleQuit() {
        quitAction()
    }
}
