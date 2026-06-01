import Foundation
import Security
import HelioCore

/// Stores the apptoken in the keychain; host in UserDefaults alongside.
struct KeychainTokenStore: TokenStoring {
    private let account = "zepp-apptoken"
    private let service = "com.helio.HelioBar"
    private let hostKey = "zepp-host"

    func save(_ creds: ZeppCredentials) throws {
        try clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(creds.appToken.utf8),
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.os(status) }
        UserDefaults.standard.set(creds.host, forKey: hostKey)
    }

    func load() -> ZeppCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              let host = UserDefaults.standard.string(forKey: hostKey)
        else { return nil }
        return ZeppCredentials(appToken: token, host: host)
    }

    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.os(status)
        }
        UserDefaults.standard.removeObject(forKey: hostKey)
    }

    enum KeychainError: Error { case os(OSStatus) }
}
