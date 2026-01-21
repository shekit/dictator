import AppKit
import Carbon

/// Manages global hotkey detection using CGEvent taps.
/// Detects hold (fn key down) and release (fn key up) events.
/// Cancels recording if another key is pressed while fn is held (e.g., F1-F12).
final class GlobalHotkeyManager {
    // MARK: - Types

    enum HotkeyEvent {
        case keyDown      // fn pressed - start recording
        case keyUp        // fn released - complete recording
        case cancelled    // fn + other key - cancel recording
    }

    typealias HotkeyHandler = (HotkeyEvent) -> Void

    // MARK: - Properties

    /// Using nonisolated(unsafe) to store the event tap safely across threads
    nonisolated(unsafe) private var eventTap: CFMachPort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?

    private var isFnPressed = false
    private var wasOtherKeyPressed = false
    private let handler: HotkeyHandler

    /// fn key code
    private let fnKeyCode: Int64 = 63  // 0x3F

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
        print("[Hotkey] Global hotkey manager started (fn key - hold to record)")
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
        // Listen for key events and flags changed (for fn key)
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

        print("[Hotkey] Event tap created and enabled")
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

        // Handle flagsChanged - this is where we detect fn key press/release
        if type == .flagsChanged {
            // fn key has keycode 63
            if keyCode == fnKeyCode {
                // Check if fn flag is now set (key pressed) or cleared (key released)
                let fnFlagSet = flags.contains(.maskSecondaryFn)

                if fnFlagSet && !isFnPressed {
                    // fn key just pressed
                    handleFnDown()
                } else if !fnFlagSet && isFnPressed {
                    // fn key just released
                    handleFnUp()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        // If fn is pressed and any other key is pressed, cancel recording
        if type == .keyDown && isFnPressed {
            print("[Hotkey] Other key pressed while fn held (keyCode: \(keyCode)) - cancelling")
            wasOtherKeyPressed = true
            handleCancelled()
            // Let the event pass through (e.g., for F1-F12 functionality)
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleFnDown() {
        isFnPressed = true
        wasOtherKeyPressed = false
        print("[Hotkey] fn key pressed (key down) - Recording started")

        // Call handler on main thread
        DispatchQueue.main.async { [weak self] in
            self?.handler(.keyDown)
        }
    }

    private func handleFnUp() {
        let wasCancelled = wasOtherKeyPressed
        isFnPressed = false
        wasOtherKeyPressed = false

        if wasCancelled {
            print("[Hotkey] fn key released (was cancelled)")
            // Already cancelled, don't send keyUp
        } else {
            print("[Hotkey] fn key released (key up) - Recording stopped")
            // Call handler on main thread
            DispatchQueue.main.async { [weak self] in
                self?.handler(.keyUp)
            }
        }
    }

    private func handleCancelled() {
        // Call handler on main thread
        DispatchQueue.main.async { [weak self] in
            self?.handler(.cancelled)
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
