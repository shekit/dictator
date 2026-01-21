import Foundation
import Security

/// Secure storage for API keys using macOS Keychain.
final class KeychainManager {
    // MARK: - Singleton

    static let shared = KeychainManager()

    // MARK: - Constants

    private let service = "com.dictator.apikeys"
    private let openRouterKeyAccount = "openrouter_api_key"

    // MARK: - Initialization

    private init() {}

    // MARK: - OpenRouter API Key

    var openRouterAPIKey: String? {
        get { retrieveKey(account: openRouterKeyAccount) }
        set {
            if let newValue = newValue {
                storeKey(newValue, account: openRouterKeyAccount)
            } else {
                deleteKey(account: openRouterKeyAccount)
            }
        }
    }

    // MARK: - Private Methods

    private func storeKey(_ key: String, account: String) {
        // Delete existing item first
        deleteKey(account: account)

        // Add new item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[Keychain] Failed to store key: \(status)")
        } else {
            print("[Keychain] Key stored successfully for account: \(account)")
        }
    }

    private func retrieveKey(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    private func deleteKey(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
