import Foundation
import NexusCore
import Security

enum KeychainCredentialError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
            return "Keychain error: \(message)"
        }
    }
}

struct KeychainCredentialStore {
    static let contextModelService = "com.nexus.context-model"

    func loadKey(for provider: ContextModelProvider) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.contextModelService,
            kSecAttrAccount as String: account(for: provider),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainCredentialError.unexpectedStatus(status) }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveKey(_ key: String, for provider: ContextModelProvider) throws {
        let itemQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.contextModelService,
            kSecAttrAccount as String: account(for: provider),
        ]
        let update: [String: Any] = [
            kSecValueData as String: Data(key.utf8)
        ]
        let updateStatus = SecItemUpdate(itemQuery as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainCredentialError.unexpectedStatus(updateStatus)
        }

        let newItem = itemQuery.merging([
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(key.utf8),
        ]) { _, newValue in newValue }
        let status = SecItemAdd(newItem as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainCredentialError.unexpectedStatus(status) }
    }

    func deleteKey(for provider: ContextModelProvider) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.contextModelService,
            kSecAttrAccount as String: account(for: provider),
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialError.unexpectedStatus(status)
        }
    }

    private func account(for provider: ContextModelProvider) -> String {
        "\(provider.rawValue)-api-key"
    }
}
