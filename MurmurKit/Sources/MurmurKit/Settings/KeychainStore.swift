import Foundation
import Security

/// Stores API keys in the macOS Keychain (generic passwords). Keys never touch
/// `UserDefaults`, logs, or settings exports.
public struct KeychainStore: Sendable {
    public let service: String

    public init(service: String = "com.murmur.app") {
        self.service = service
    }

    /// Set (or, with `nil`, delete) the value for an account.
    public func set(_ value: String?, for account: String) {
        guard let value, !value.isEmpty else {
            delete(account)
            return
        }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                Log.settings.error("Keychain add failed for \(account, privacy: .public): \(addStatus)")
            }
        } else if status != errSecSuccess {
            Log.settings.error("Keychain update failed for \(account, privacy: .public): \(status)")
        }
    }

    /// Read the value for an account, or `nil` if absent.
    public func value(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Log.settings.error("Keychain delete failed for \(account, privacy: .public): \(status)")
        }
    }

    public func hasValue(for account: String) -> Bool {
        value(for: account) != nil
    }
}
