import AppKit
import Combine

@MainActor
final class StatusBarController {
    // MARK: - Types

    enum IconState {
        case idle
        case recording
        case processing
        case error
    }

    // MARK: - Properties

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let quitItem: NSMenuItem
    private let statusMenuItem = NSMenuItem()
    private let quitAction: () -> Void

    private var recordingService: RecordingService?
    private var cancellables = Set<AnyCancellable>()

    private let normalIcon = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Dictator")
    private let recordingIcon = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "Recording")
    private let processingIcon = NSImage(systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: "Processing")
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
        case .processing:
            icon = processingIcon
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

        let separatorItem = NSMenuItem.separator()

        menu.items = [
            statusMenuItem,
            separatorItem,
            quitItem
        ]
        statusItem.menu = menu
    }

    private func handleStateChange(_ state: RecordingService.State) {
        switch state {
        case .idle:
            setIconState(.idle)
            statusMenuItem.title = "Status: Ready"
        case .recording:
            setIconState(.recording)
            statusMenuItem.title = "Status: Recording..."
        case .processing:
            setIconState(.processing)
            statusMenuItem.title = "Status: Processing..."
        case .error(let message):
            setIconState(.error)
            statusMenuItem.title = "Error: \(message)"
        }
    }

    @objc private func handleQuit() {
        quitAction()
    }
}
