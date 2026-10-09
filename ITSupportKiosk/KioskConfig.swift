import Foundation

enum KioskConfig {
    static let homeURL = URL(string: "https://wiki.yandex.ru/sd-portal/it-support/it-support-office/")!

    /// Домены, по которым пользователь может свободно ходить. Разрешены и все их поддомены.
    static let allowedDomains: Set<String> = [
        "yandex.ru",
    ]

    /// Хосты Яндекс ID: на них запускается автовход и не срабатывает возврат по бездействию.
    static let authHosts: Set<String> = [
        "passport.yandex.ru",
        "sso.passport.yandex.ru",
        "sso.yandex.ru",
    ]

    static let idleTimeout: TimeInterval = 30

    /// Меню администратора: долгое нажатие на кнопку «Домой» + PIN. Обязательно смените PIN.
    static let adminPIN = "246810"
    static let adminLongPressDuration: TimeInterval = 5

    /// Защита от блокировки учётки: не больше N отправок пароля за окно времени.
    static let maxPasswordSubmissions = 3
    static let passwordSubmissionWindow: TimeInterval = 300

    static func isAllowedHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return allowedDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func isAuthHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return authHosts.contains(host)
    }
}
