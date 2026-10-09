import Foundation
import Security

struct Credentials: Codable {
    let login: String
    let password: String
}

/// Логин и пароль сервисной учётной записи хранятся в Keychain устройства, а не в коде.
enum CredentialsStore {
    private static let baseQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "kiosk.yandex-id",
        kSecAttrAccount as String: "service-account",
    ]

    static func load() -> Credentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    @discardableResult
    static func save(_ credentials: Credentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
