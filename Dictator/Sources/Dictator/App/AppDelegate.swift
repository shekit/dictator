import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController { [weak self] in
            self?.terminate()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController = nil
    }

    private func terminate() {
        NSApp.terminate(nil)
    }
}
