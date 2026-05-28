import Foundation
import Security

/// Secure storage for API keys, backed by the macOS Keychain.
/// Keys are never written to disk in plaintext, to UserDefaults, or to the repo.
enum KeychainStore {
    private static let service = Bundle.main.bundleIdentifier ?? "com.joseph.Council"

    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    /// Save (or overwrite) a secret for the given account.
    static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)

        // Remove any existing item first, then add a fresh one (simpler than an update).
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    service,
            kSecAttrAccount as String:    account,
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Read the secret for the given account, or nil if none is stored.
    static func read(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Delete the secret for the given account. Returns true if it is gone afterwards.
    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

#if DEBUG
extension KeychainStore {
    /// Temporary self-check: save → read → delete a throwaway value, printing the result
    /// to the Xcode console. Removed once SetupView exercises the store for real.
    static func debugRoundTrip() {
        let account = "debug.roundtrip"
        do {
            try save("hello-council-123", account: account)
            let value = try read(account: account)
            print("[KeychainStore] save→read: '\(value ?? "nil")' — \(value == "hello-council-123" ? "✅ MATCH" : "❌ MISMATCH")")

            delete(account: account)
            let afterDelete = try read(account: account)
            print("[KeychainStore] after delete: \(afterDelete == nil ? "✅ nil (silindi)" : "❌ hâlâ duruyor")")
        } catch {
            print("[KeychainStore] ❌ error: \(error)")
        }
    }
}
#endif
