import AppKit
import Carbon

/// Manages global hotkey detection using CGEvent taps.
/// Detects hold (key down) and release (key up) events for Ctrl+Option+Space.
final class GlobalHotkeyManager {
    // MARK: - Types

    enum HotkeyEvent {
        case keyDown
        case keyUp
    }

    typealias HotkeyHandler = (HotkeyEvent) -> Void

    // MARK: - Properties

    /// Using nonisolated(unsafe) to store the event tap safely across threads
    nonisolated(unsafe) private var eventTap: CFMachPort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?

    private var isKeyPressed = false
    private let handler: HotkeyHandler

    /// Hotkey configuration: Ctrl + Option + Space
    private let targetKeyCode: CGKeyCode = 49  // Space bar
    private let requiredModifiers: CGEventFlags = [.maskControl, .maskAlternate]

    private var healthCheckTimer: Timer?

    // MARK: - Initialization

    init(handler: @escaping HotkeyHandler) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods

    /// Start listening for global hotkey events.
    /// Should be called after a delay (1-2 seconds) from app launch.
    func start() {
        guard AXIsProcessTrusted() else {
            print("[Hotkey] Accessibility permission not granted. Please enable in System Settings.")
            promptForAccessibility()
            return
        }

        setupEventTap()
        startHealthCheck()
        print("[Hotkey] Global hotkey manager started (Ctrl+Option+Space)")
    }

    /// Stop listening for global hotkey events.
    func stop() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }

        print("[Hotkey] Global hotkey manager stopped")
    }

    // MARK: - Private Methods

    private func setupEventTap() {
        // Listen for key down and key up events, plus flags changed for modifier tracking
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                      (1 << CGEventType.keyUp.rawValue) |
                                      (1 << CGEventType.flagsChanged.rawValue) |
                                      (1 << CGEventType.tapDisabledByTimeout.rawValue) |
                                      (1 << CGEventType.tapDisabledByUserInput.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        )

        guard let tap = eventTap else {
            print("[Hotkey] Failed to create event tap. Check accessibility permissions.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        guard let source = runLoopSource else {
            print("[Hotkey] Failed to create run loop source")
            eventTap = nil
            return
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle tap disabled events - re-enable immediately
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            print("[Hotkey] Event tap was disabled, re-enabling...")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Check if this is our target hotkey
        guard keyCode == targetKeyCode,
              flags.contains(requiredModifiers) else {
            // If key was pressed and modifiers released, treat as key up
            if isKeyPressed && !flags.contains(requiredModifiers) {
                handleKeyUp()
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            if !isKeyPressed {
                handleKeyDown()
            }
            // Consume the event to prevent it from being passed to other apps
            return nil

        case .keyUp:
            if isKeyPressed {
                handleKeyUp()
            }
            // Consume the event
            return nil

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown() {
        isKeyPressed = true
        print("[Hotkey] Hotkey pressed (key down)")

        // Call handler on main thread
        DispatchQueue.main.async { [weak self] in
            self?.handler(.keyDown)
        }
    }

    private func handleKeyUp() {
        isKeyPressed = false
        print("[Hotkey] Hotkey released (key up)")

        // Call handler on main thread
        DispatchQueue.main.async { [weak self] in
            self?.handler(.keyUp)
        }
    }

    private func startHealthCheck() {
        // Check every 30 seconds if tap is still enabled
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.checkTapHealth()
        }
    }

    private func checkTapHealth() {
        guard let tap = eventTap else { return }

        if !CGEvent.tapIsEnabled(tap: tap) {
            print("[Hotkey] Event tap was disabled, re-enabling...")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func promptForAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }
}
