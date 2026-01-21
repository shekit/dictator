import AppKit
import Carbon

/// Service for injecting text at the current cursor position.
/// Uses clipboard-based injection with Cmd+V simulation.
@MainActor
final class TextInjectionService {
    // MARK: - Singleton

    static let shared = TextInjectionService()

    // MARK: - Properties

    /// Stores the original clipboard contents for restoration
    private var savedClipboardItems: [NSPasteboardItem]?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Check if Accessibility permission is granted
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Request Accessibility permission from the user
    func requestAccessibilityPermission() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        AXIsProcessTrustedWithOptions(options)

        // Also open the Privacy & Security pane for convenience
        openAccessibilitySettings()
    }

    /// Open the Accessibility settings pane
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Inject text at the current cursor position.
    /// Uses the clipboard + Cmd+V pattern with clipboard restoration.
    /// - Parameter text: The text to inject
    /// - Returns: True if injection succeeded, false otherwise
    func injectText(_ text: String) async -> Bool {
        guard !text.isEmpty else {
            print("[TextInjection] Empty text, skipping injection")
            return false
        }

        guard hasAccessibilityPermission else {
            print("[TextInjection] Accessibility permission not granted")
            requestAccessibilityPermission()
            return false
        }

        print("[TextInjection] Injecting text: '\(text.prefix(50))...'")

        // Step 1: Save current clipboard contents
        saveClipboard()

        // Step 2: Write our text to clipboard
        writeToClipboard(text)

        // Step 3: Small delay to ensure clipboard is ready
        try? await Task.sleep(for: .milliseconds(50))

        // Step 4: Simulate Cmd+V keystroke
        let success = simulatePaste()

        // Step 5: Delay to allow paste to complete
        try? await Task.sleep(for: .milliseconds(100))

        // Step 6: Restore original clipboard
        restoreClipboard()

        if success {
            print("[TextInjection] Text injected successfully")
        } else {
            print("[TextInjection] Failed to inject text")
        }

        return success
    }

    // MARK: - Private Methods - Clipboard Operations

    /// Save the current clipboard contents for later restoration
    private func saveClipboard() {
        let pasteboard = NSPasteboard.general

        // Store all items from the clipboard
        if let items = pasteboard.pasteboardItems {
            savedClipboardItems = items.compactMap { item -> NSPasteboardItem? in
                let newItem = NSPasteboardItem()

                // Copy all types from the original item
                for type in item.types {
                    if let data = item.data(forType: type) {
                        newItem.setData(data, forType: type)
                    }
                }

                return newItem
            }
            print("[TextInjection] Saved clipboard with \(savedClipboardItems?.count ?? 0) items")
        } else {
            savedClipboardItems = nil
            print("[TextInjection] No clipboard contents to save")
        }
    }

    /// Write text to the clipboard
    private func writeToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("[TextInjection] Wrote text to clipboard")
    }

    /// Restore the previously saved clipboard contents
    private func restoreClipboard() {
        let pasteboard = NSPasteboard.general

        guard let items = savedClipboardItems, !items.isEmpty else {
            // Nothing to restore - clipboard was empty before
            print("[TextInjection] No clipboard contents to restore")
            savedClipboardItems = nil
            return
        }

        pasteboard.clearContents()
        pasteboard.writeObjects(items)

        print("[TextInjection] Restored original clipboard")
        savedClipboardItems = nil
    }

    // MARK: - Private Methods - Keystroke Simulation

    /// Simulate Cmd+V keystroke to paste clipboard contents
    private func simulatePaste() -> Bool {
        // Get the 'V' key code (key code 9 on US keyboard)
        let vKeyCode: CGKeyCode = 9

        // Create key down event with Command modifier
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true) else {
            print("[TextInjection] Failed to create key down event")
            return false
        }
        keyDown.flags = .maskCommand

        // Create key up event with Command modifier
        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else {
            print("[TextInjection] Failed to create key up event")
            return false
        }
        keyUp.flags = .maskCommand

        // Post the events
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        print("[TextInjection] Simulated Cmd+V keystroke")
        return true
    }
}
