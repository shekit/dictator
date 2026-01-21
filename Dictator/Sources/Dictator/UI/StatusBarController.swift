import AppKit

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let quitItem = NSMenuItem(title: "Quit Dictator", action: #selector(handleQuit), keyEquivalent: "q")
    private let quitAction: () -> Void

    init(quitAction: @escaping () -> Void) {
        self.quitAction = quitAction
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        configureButton()
        configureMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }

        // Use SF Symbol for menu bar icon
        if let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Dictator") {
            image.isTemplate = true
            button.image = image
        }
    }

    private func configureMenu() {
        quitItem.target = self

        menu.items = [
            quitItem
        ]
        statusItem.menu = menu
    }

    @objc private func handleQuit() {
        quitAction()
    }
}
