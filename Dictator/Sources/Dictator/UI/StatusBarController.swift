import AppKit
import SwiftUI
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
    private let settingsItem: NSMenuItem
    private let completeSetupItem: NSMenuItem
    private let statusMenuItem = NSMenuItem()
    private let statsMenuItem = NSMenuItem()
    private var modeMenuItems: [NSMenuItem] = []
    private let quitAction: () -> Void
    private var isOnboardingComplete = true

    private var recordingService: RecordingService?
    private var llmService: LLMService?
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindowController: NSWindowController?

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
        self.settingsItem = NSMenuItem(title: "Settings...", action: nil, keyEquivalent: ",")
        self.completeSetupItem = NSMenuItem(title: "Complete Setup...", action: nil, keyEquivalent: "")
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

        // Observe Ollama availability changes
        service.$isOllamaAvailable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLLMMenuItems()
            }
            .store(in: &cancellables)

        // Initial update
        updateLLMMenuItems()
    }

    /// Set onboarding completion status and update menu
    func setOnboardingComplete(_ isComplete: Bool) {
        isOnboardingComplete = isComplete
        updateMenuForOnboardingStatus()
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

    /// Update today's stats display in the menu.
    func updateTodayStats() {
        let stats = StatsService.shared.todayStats
        if stats.recordingCount == 0 {
            statsMenuItem.title = "Today: No recordings yet"
        } else {
            let avgWPM = String(format: "%.0f", stats.averageWPM)
            statsMenuItem.title = "Today: \(stats.totalWords) words | \(avgWPM) WPM"
        }
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

        settingsItem.target = self
        settingsItem.action = #selector(handleSettings)

        completeSetupItem.target = self
        completeSetupItem.action = #selector(handleCompleteSetup)

        // Stats display item (disabled, just for info)
        updateTodayStats()
        statsMenuItem.isEnabled = false

        // Build mode menu items
        buildModeMenuItems()

        // Build initial menu
        updateMenuForOnboardingStatus()

        // Assign menu to status item
        statusItem.menu = menu
    }

    private func updateMenuForOnboardingStatus() {
        // Build menu with mode items directly in main menu
        var menuItems: [NSMenuItem] = [
            statsMenuItem,
            NSMenuItem.separator()
        ]
        menuItems.append(contentsOf: modeMenuItems)
        menuItems.append(contentsOf: [
            NSMenuItem.separator()
        ])

        // Add "Complete Setup..." if onboarding not complete
        if !isOnboardingComplete {
            menuItems.append(completeSetupItem)
            menuItems.append(NSMenuItem.separator())
        }

        menuItems.append(contentsOf: [
            settingsItem,
            NSMenuItem.separator(),
            quitItem
        ])

        menu.items = menuItems
    }

    private func buildModeMenuItems() {
        modeMenuItems.removeAll()

        guard let service = llmService else { return }

        // Add subtitle header
        let subtitleItem = NSMenuItem(title: "LLM Post Processing", action: nil, keyEquivalent: "")
        subtitleItem.isEnabled = false
        modeMenuItems.append(subtitleItem)

        // Iterate through modes in specific order: off, local, cloud
        let orderedModes: [LLMService.ProcessingMode] = [.off, .local, .cloud]

        for mode in orderedModes {
            var title = mode.displayName

            // Add status indicators for unavailable services
            if mode == .cloud && !EnvLoader.shared.hasOpenRouterKey {
                title = "Cloud - API key missing"
            } else if mode == .local && !service.isOllamaAvailable {
                title = "Local - Ollama not connected"
            }

            let item = NSMenuItem(title: title, action: #selector(handleModeSelection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode.rawValue == service.processingMode.rawValue ? .on : .off
            modeMenuItems.append(item)
        }
    }


    private func updateLLMMenuItems() {
        // Rebuild mode menu items to update availability status and checkmarks
        buildModeMenuItems()

        // Rebuild entire menu to reflect updated mode items
        var menuItems: [NSMenuItem] = [
            statsMenuItem,
            NSMenuItem.separator()
        ]
        menuItems.append(contentsOf: modeMenuItems)
        menuItems.append(contentsOf: [
            NSMenuItem.separator(),
            settingsItem,
            NSMenuItem.separator(),
            quitItem
        ])
        menu.items = menuItems
    }

    @objc private func handleModeSelection(_ sender: NSMenuItem) {
        guard let service = llmService,
              let modeRaw = sender.representedObject as? String,
              let mode = LLMService.ProcessingMode(rawValue: modeRaw) else { return }

        // If switching to cloud mode, check for API key
        if mode == .cloud && !EnvLoader.shared.hasOpenRouterKey {
            let alert = NSAlert()
            alert.messageText = "OpenRouter API Key Required"
            alert.informativeText = "To use Cloud mode, you need to add your OpenRouter API key.\n\nOpen Settings from the menu bar and enter your API key."
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


    private func handleStateChange(_ state: RecordingService.State) {
        switch state {
        case .idle:
            setIconState(.idle)
        case .recording:
            setIconState(.recording)
        case .transcribing:
            setIconState(.transcribing)
        case .processing:
            setIconState(.processing)
        case .injecting:
            setIconState(.injecting)
        case .error(_):
            setIconState(.error)
        }
    }

    @objc private func handleSettings() {
        // Create settings window if it doesn't exist
        if settingsWindowController == nil {
            guard let service = llmService else { return }

            let settingsView = SettingsWindow(llmService: service)
            let hostingController = NSHostingController(rootView: settingsView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "Dictator Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 600, height: 500))
            window.center()

            let windowController = NSWindowController(window: window)
            settingsWindowController = windowController
        }

        // Show the window
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func handleCompleteSetup() {
        // Get the app delegate and show onboarding
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showOnboarding()
        }
    }

    @objc private func handleQuit() {
        quitAction()
    }
}
