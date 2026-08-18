import Foundation
import Security

enum KeychainStorage {
    private static let notionTokenService = "com.kevinwolfrom.umbrella.notion-token"
    private static let notionTokenAccount = "default"
    private static let notionTokenLabel = "Umbrella Helper Notion Token"
    // Pre-rename service name; read once so existing tokens migrate silently.
    private static let legacyNotionTokenService = "com.cursorpopup.notion-token"

    static var notionToken: String? {
        if let token = read(service: notionTokenService, account: notionTokenAccount) {
            return token
        }
        guard let legacy = read(service: legacyNotionTokenService, account: notionTokenAccount) else {
            return nil
        }
        // Only drop the legacy item after the new service reads back successfully.
        if store(legacy, service: notionTokenService, account: notionTokenAccount, label: notionTokenLabel),
           read(service: notionTokenService, account: notionTokenAccount) == legacy {
            delete(service: legacyNotionTokenService, account: notionTokenAccount)
        }
        return legacy
    }

    /// Stores the Notion token. Returns true only after a matching Keychain read-back.
    @discardableResult
    static func storeNotionToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return store(trimmed, service: notionTokenService, account: notionTokenAccount, label: notionTokenLabel)
    }

    static func clearNotionToken() {
        delete(service: notionTokenService, account: notionTokenAccount)
    }

    /// Updates or adds without deleting first. Returns true only after a matching read-back.
    @discardableResult
    private static func store(_ value: String, service: String, account: String, label: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: label,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return read(service: service, account: account) == value
        }

        guard updateStatus == errSecItemNotFound else {
            return false
        }

        var addQuery = baseQuery
        addQuery[kSecAttrLabel as String] = label
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { return false }
        return read(service: service, account: account) == value
    }

    private static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
