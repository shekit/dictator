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
    private let llmToggleMenuItem = NSMenuItem()
    private var modelSubmenu = NSMenu()
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
            .sink { [weak self] mode in
                self?.updateLLMMenuItems()
            }
            .store(in: &cancellables)

        // Observe model changes
        service.$selectedCloudModel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLLMMenuItems()
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

        // LLM processing toggle
        llmToggleMenuItem.title = "Enable LLM Processing"
        llmToggleMenuItem.target = self
        llmToggleMenuItem.action = #selector(handleLLMToggle)
        llmToggleMenuItem.state = .on

        // Model selection submenu
        let modelMenuItem = NSMenuItem(title: "Cloud Model", action: nil, keyEquivalent: "")
        buildModelSubmenu()
        modelMenuItem.submenu = modelSubmenu

        menu.items = [
            statusMenuItem,
            NSMenuItem.separator(),
            llmStatusMenuItem,
            llmToggleMenuItem,
            modelMenuItem,
            NSMenuItem.separator(),
            quitItem
        ]
        statusItem.menu = menu
    }

    private func buildModelSubmenu() {
        modelSubmenu.removeAllItems()

        for model in OpenRouterClient.availableModels {
            let item = NSMenuItem(title: model.name, action: #selector(handleModelSelection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model.id
            modelSubmenu.addItem(item)
        }
    }

    private func updateLLMMenuItems() {
        guard let service = llmService else { return }

        // Update status display
        llmStatusMenuItem.title = "LLM: \(service.modeStatusDescription)"

        // Update toggle state
        llmToggleMenuItem.state = service.processingMode != .off ? .on : .off
        llmToggleMenuItem.title = service.processingMode != .off ? "Disable LLM Processing" : "Enable LLM Processing"

        // Update model checkmarks
        for item in modelSubmenu.items {
            if let modelId = item.representedObject as? String {
                item.state = modelId == service.selectedCloudModel ? .on : .off
            }
        }

        // Disable model selection if LLM is off or in local mode
        let enableModelSelection = service.processingMode == .cloud
        for item in modelSubmenu.items {
            item.isEnabled = enableModelSelection
        }
    }

    @objc private func handleLLMToggle() {
        guard let service = llmService else { return }

        if service.processingMode == .off {
            // Turn on - check if we have API key
            if EnvLoader.shared.hasOpenRouterKey {
                service.processingMode = .cloud
            } else {
                // Show alert about missing API key
                let alert = NSAlert()
                alert.messageText = "OpenRouter API Key Required"
                alert.informativeText = "To enable LLM processing, add OPENROUTER_API_KEY to your .env file.\n\nExpected location: \(EnvLoader.shared.envFileLocation ?? "~/.env or ~/Documents/Dictator/.env")"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } else {
            // Turn off
            service.processingMode = .off
        }
    }

    @objc private func handleModelSelection(_ sender: NSMenuItem) {
        guard let service = llmService,
              let modelId = sender.representedObject as? String else { return }

        service.selectedCloudModel = modelId
        print("[StatusBarController] Model changed to: \(modelId)")
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
