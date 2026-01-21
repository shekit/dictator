import AppKit
import ApplicationServices
import Carbon

/// Service for injecting text at the current cursor position.
/// Uses multiple strategies for reliability across different apps.
@MainActor
final class TextInjectionService {
    // MARK: - Singleton

    static let shared = TextInjectionService()

    // MARK: - Properties

    private var isCurrentlyInjecting = false

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
    /// Uses multiple strategies for reliability.
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

        // Prevent concurrent injection operations
        guard !isCurrentlyInjecting else {
            print("[TextInjection] Already injecting, skipping")
            return false
        }

        isCurrentlyInjecting = true
        defer { isCurrentlyInjecting = false }

        print("[TextInjection] Injecting text: '\(text.prefix(50))...'")

        // Run injection on background thread to avoid blocking
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                // Small delay to ensure target app is ready
                usleep(100_000) // 100ms

                let success = self.performInjection(text)
                continuation.resume(returning: success)
            }
        }
    }

    // MARK: - Private Methods - Injection Pipeline

    /// Performs the actual injection using multiple strategies
    private nonisolated func performInjection(_ text: String) -> Bool {
        // Strategy 1: Get the focused element's PID and post unicode CGEvents directly
        if let focusedPID = Self.captureSystemFocusedPID() {
            print("[TextInjection] Trying CGEvent unicode to focused PID \(focusedPID)")
            if insertTextViaCGEventUnicode(text, targetPID: focusedPID) {
                print("[TextInjection] SUCCESS: CGEvent unicode to PID \(focusedPID)")
                return true
            }
        }

        // Strategy 2: Try Accessibility API to set text directly
        print("[TextInjection] Trying Accessibility API insertion")
        if insertTextViaAccessibility(text) {
            print("[TextInjection] SUCCESS: Accessibility API insertion")
            return true
        }

        // Strategy 3: Clipboard fallback with Cmd+V to frontmost app
        print("[TextInjection] Trying clipboard fallback")
        if insertTextViaClipboard(text) {
            print("[TextInjection] SUCCESS: Clipboard insertion")
            return true
        }

        print("[TextInjection] All injection strategies failed")
        return false
    }

    // MARK: - Focus Helpers

    /// Returns the PID owning the currently focused accessibility element.
    static nonisolated func captureSystemFocusedPID() -> pid_t? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard result == .success, let focusedElementRef else { return nil }
        guard CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else { return nil }

        let element = unsafeBitCast(focusedElementRef, to: AXUIElement.self)
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid > 0 else { return nil }
        return pid
    }

    // MARK: - Strategy 1: CGEvent Unicode

    /// Insert text by posting CGEvent with unicode string directly to PID
    private nonisolated func insertTextViaCGEventUnicode(_ text: String, targetPID: pid_t) -> Bool {
        guard targetPID > 0 else {
            print("[TextInjection] Invalid target PID")
            return false
        }

        // Convert text to UTF16 array
        let utf16Array = Array(text.utf16)

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        else {
            print("[TextInjection] Failed to create CGEvents")
            return false
        }

        // Set the unicode string for both events
        keyDown.keyboardSetUnicodeString(stringLength: utf16Array.count, unicodeString: utf16Array)
        keyUp.keyboardSetUnicodeString(stringLength: utf16Array.count, unicodeString: utf16Array)

        // Post events to the specific application
        keyDown.postToPid(targetPID)
        usleep(2000) // 2ms delay
        keyUp.postToPid(targetPID)

        print("[TextInjection] Posted unicode CGEvents to PID \(targetPID)")
        return true
    }

    // MARK: - Strategy 2: Accessibility API

    /// Insert text using Accessibility API
    private nonisolated func insertTextViaAccessibility(_ text: String) -> Bool {
        guard let focusedElement = getFocusedTextElement() else {
            print("[TextInjection] Could not find focused text element")
            return false
        }

        // Try to insert at cursor position using selected range
        if insertTextAtCursor(focusedElement, text) {
            return true
        }

        // Try setting value directly
        let cfText = text as CFString
        let result = AXUIElementSetAttributeValue(focusedElement, kAXValueAttribute as CFString, cfText)
        if result == .success {
            print("[TextInjection] Set text via kAXValueAttribute")
            return true
        }

        // Try setting selected text
        let selResult = AXUIElementSetAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, cfText)
        if selResult == .success {
            print("[TextInjection] Set text via kAXSelectedTextAttribute")
            return true
        }

        return false
    }

    private nonisolated func getFocusedTextElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        if result == .success, let focusedElement {
            guard CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(focusedElement, to: AXUIElement.self)
        }

        return nil
    }

    private nonisolated func insertTextAtCursor(_ element: AXUIElement, _ text: String) -> Bool {
        // Get current value
        var valueRef: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        guard valueResult == .success, let currentValue = valueRef as? String else {
            return false
        }

        // Get selected text range (cursor position)
        var rangeRef: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        guard rangeResult == .success, let rangeRef else { return false }
        guard CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return false }

        var range = CFRange()
        let ok = AXValueGetValue(unsafeBitCast(rangeRef, to: AXValue.self), .cfRange, &range)
        guard ok else { return false }

        // Insert text at cursor position
        let nsString = currentValue as NSString
        let maxLen = nsString.length
        let safeLoc = max(0, min(range.location, maxLen))
        let safeLen = max(0, min(range.length, maxLen - safeLoc))

        let mutable = NSMutableString(string: currentValue)
        mutable.replaceCharacters(in: NSRange(location: safeLoc, length: safeLen), with: text)
        let newValue = mutable as String

        // Set the new value
        let setResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue as CFString)
        guard setResult == .success else { return false }

        // Move cursor to end of inserted text
        let insertedLen = (text as NSString).length
        var newRange = CFRange(location: safeLoc + insertedLen, length: 0)
        if let axRange = AXValueCreate(.cfRange, &newRange) {
            _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
        }

        print("[TextInjection] Inserted text at cursor via Accessibility")
        return true
    }

    // MARK: - Strategy 3: Clipboard Fallback

    /// Insert text via clipboard + Cmd+V
    private nonisolated func insertTextViaClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general

        // Save current clipboard (local variable, not instance state)
        let previousContent = pasteboard.string(forType: .string)

        // Set our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Get frontmost app PID for targeted paste
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            print("[TextInjection] No frontmost application")
            // Restore clipboard
            if let prev = previousContent {
                pasteboard.clearContents()
                pasteboard.setString(prev, forType: .string)
            }
            return false
        }
        let pid = frontApp.processIdentifier

        // Create Cmd+V events
        let vKeyCode: CGKeyCode = 9 // 'V' key

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false)
        else {
            print("[TextInjection] Failed to create Cmd+V events")
            // Restore clipboard
            if let prev = previousContent {
                pasteboard.clearContents()
                pasteboard.setString(prev, forType: .string)
            }
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // Post to specific app (safer than HID tap)
        keyDown.postToPid(pid)
        usleep(10_000) // 10ms
        keyUp.postToPid(pid)

        print("[TextInjection] Sent Cmd+V to PID \(pid) (\(frontApp.localizedName ?? "unknown"))")

        // Restore clipboard after a delay
        usleep(150_000) // 150ms for paste to complete
        if let prev = previousContent {
            pasteboard.clearContents()
            pasteboard.setString(prev, forType: .string)
            print("[TextInjection] Restored original clipboard")
        }

        return true
    }
}
