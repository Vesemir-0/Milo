import Foundation
import Security

protocol SecretStoring {
    func saveAPIKey(_ value: String, for account: String) throws
    func getAPIKey(for account: String) throws -> String
    func deleteAPIKey(for account: String) throws
}
enum KeychainError: Error { case itemNotFound, invalidData, unexpectedStatus(OSStatus) }

final class KeychainService: SecretStoring {
    private let service = "com.aischeduleassistant.v2"
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    func saveAPIKey(_ apiKey: String, for account: String = "default") throws {
        guard let data = apiKey.data(using: .utf8) else { throw KeychainError.invalidData }
        let q = query(account)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = q; insert[kSecValueData as String] = data
            let add = SecItemAdd(insert as CFDictionary, nil)
            guard add == errSecSuccess else { throw KeychainError.unexpectedStatus(add) }
        } else if status != errSecSuccess { throw KeychainError.unexpectedStatus(status) }
    }
    func getAPIKey(for account: String = "default") throws -> String {
        var q = query(account)
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { throw KeychainError.itemNotFound }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw KeychainError.invalidData }
        return value
    }
    func deleteAPIKey(for account: String = "default") throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unexpectedStatus(status) }
    }
}
final class MemorySecretStore: SecretStoring {
    var values: [String: String] = [:]
    func saveAPIKey(_ value: String, for account: String) throws { values[account] = value }
    func getAPIKey(for account: String) throws -> String { guard let v = values[account] else { throw KeychainError.itemNotFound }; return v }
    func deleteAPIKey(for account: String) throws { values.removeValue(forKey: account) }
}
