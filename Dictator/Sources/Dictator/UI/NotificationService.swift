import AppKit
import UserNotifications

/// Handles system notifications and error alerts.
@MainActor
final class NotificationService {
    // MARK: - Singleton

    static let shared = NotificationService()

    // MARK: - Initialization

    private init() {
        requestAuthorization()
    }

    // MARK: - Public Methods

    /// Request notification permission (non-blocking).
    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("[NotificationService] Authorization error: \(error)")
            } else if !granted {
                print("[NotificationService] Notification permission denied")
            }
        }
    }

    /// Show an error notification.
    /// - Parameters:
    ///   - title: Error title
    ///   - message: Error message
    func showError(title: String = "Dictator Error", message: String) {
        showNotification(title: title, message: message, sound: .defaultCritical)
    }

    // MARK: - Private Methods

    private func showNotification(title: String, message: String, sound: UNNotificationSound?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        if let sound = sound {
            content.sound = sound
        }

        // Use a unique identifier with timestamp to allow multiple notifications
        let identifier = UUID().uuidString
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NotificationService] Failed to show notification: \(error)")
                // Fallback to console log
                print("[NotificationService] \(title): \(message)")
            }
        }
    }
}
