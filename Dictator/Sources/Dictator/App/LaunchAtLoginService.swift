import AppKit
import ServiceManagement

/// Manages launch at login functionality using ServiceManagement framework.
final class LaunchAtLoginService: ObservableObject {
    // MARK: - Singleton

    static let shared = LaunchAtLoginService()

    // MARK: - Published Properties

    @Published var isEnabled: Bool = false

    // MARK: - Initialization

    private init() {
        updateStatus()
    }

    // MARK: - Public Methods

    /// Enable or disable launch at login.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                // Register the app to launch at login
                if #available(macOS 13.0, *) {
                    try SMAppService.mainApp.register()
                } else {
                    // Fallback for macOS 12 and earlier
                    setLaunchAtLoginLegacy(enabled: true)
                }
                print("[LaunchAtLogin] Enabled")
            } else {
                // Unregister the app from launch at login
                if #available(macOS 13.0, *) {
                    try SMAppService.mainApp.unregister()
                } else {
                    // Fallback for macOS 12 and earlier
                    setLaunchAtLoginLegacy(enabled: false)
                }
                print("[LaunchAtLogin] Disabled")
            }
            isEnabled = enabled
        } catch {
            print("[LaunchAtLogin] Failed to set launch at login: \(error)")
            // Update status to reflect actual state
            updateStatus()
        }
    }

    /// Check current launch at login status.
    func updateStatus() {
        if #available(macOS 13.0, *) {
            isEnabled = SMAppService.mainApp.status == .enabled
        } else {
            isEnabled = getLaunchAtLoginStatusLegacy()
        }
    }

    // MARK: - Private Methods (Legacy Support)

    private func setLaunchAtLoginLegacy(enabled: Bool) {
        // For macOS 12 and earlier, use LSSharedFileList
        // This is deprecated but still works
        if enabled {
            // Add to login items using AppleScript (simple fallback)
            let script = """
            tell application "System Events"
                make login item at end with properties {path:"\(Bundle.main.bundlePath)", hidden:false}
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    print("[LaunchAtLogin] AppleScript error: \(error)")
                }
            }
        } else {
            // Remove from login items
            let script = """
            tell application "System Events"
                delete login item "Dictator"
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                // Ignore errors (item might not exist)
            }
        }
    }

    private func getLaunchAtLoginStatusLegacy() -> Bool {
        // Check if app is in login items using AppleScript
        let script = """
        tell application "System Events"
            return name of every login item
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            if error == nil {
                let loginItems = result.stringValue ?? ""
                return loginItems.contains("Dictator")
            }
        }
        return false
    }
}
