import Foundation
import Security

struct Credentials: Codable {
    let login: String
    let password: String
    var totpSecret: String?
}

/// Логин, пароль и секрет TOTP сервисной учётной записи хранятся в Keychain устройства, а не в коде.
enum CredentialsStore {
    private static let baseQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "kiosk.yandex-id",
        kSecAttrAccount as String: "service-account",
    ]

    /// Файл для первичной настройки без ввода на iPad. Кладётся в Documents приложения
    /// (`xcrun devicectl device copy to …`), при запуске переносится в Keychain и удаляется.
    private static let provisioningFileName = "kiosk-credentials.json"

    private struct ProvisioningFile: Decodable {
        let login: String?
        let password: String?
        let totpSecret: String?
    }

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

    static func importProvisioningFile() {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(provisioningFileName),
              let data = try? Data(contentsOf: url)
        else { return }
        defer { try? FileManager.default.removeItem(at: url) }

        guard let file = try? JSONDecoder().decode(ProvisioningFile.self, from: data) else { return }
        let current = load()
        guard let login = file.login ?? current?.login,
              let password = file.password ?? current?.password
        else { return }
        save(Credentials(login: login, password: password, totpSecret: file.totpSecret ?? current?.totpSecret))
    }
}
