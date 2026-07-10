import Foundation
import Security

enum KeychainStorage {
    private static let notionTokenService = "com.kevinwolfrom.umbrella.notion-token"
    private static let notionTokenAccount = "default"
    private static let notionTokenLabel = "Umbrella Helper Notion Token"
    // Pre-rename service name; read once so existing tokens migrate silently.
    private static let legacyNotionTokenService = "com.cursorpopup.notion-token"

    static var notionToken: String? {
        get {
            if let token = read(service: notionTokenService, account: notionTokenAccount) {
                return token
            }
            guard let legacy = read(service: legacyNotionTokenService, account: notionTokenAccount) else {
                return nil
            }
            save(legacy, service: notionTokenService, account: notionTokenAccount, label: notionTokenLabel)
            delete(service: legacyNotionTokenService, account: notionTokenAccount)
            return legacy
        }
        set {
            if let newValue, !newValue.isEmpty {
                save(newValue, service: notionTokenService, account: notionTokenAccount, label: notionTokenLabel)
            } else {
                delete(service: notionTokenService, account: notionTokenAccount)
            }
        }
    }

    static func seedNotionTokenIfNeeded(_ token: String) {
        guard notionToken == nil || notionToken?.isEmpty == true else { return }
        notionToken = token
    }

    static func seedBootstrapCredentialsIfNeeded() {
        // Notion token is stored in Keychain via Settings.
    }

    private static func save(_ value: String, service: String, account: String, label: String) {
        delete(service: service, account: account)

        guard let data = value.data(using: .utf8) else { return }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: label,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        SecItemAdd(query as CFDictionary, nil)
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
