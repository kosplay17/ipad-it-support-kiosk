import Foundation

enum KioskConfig {
    static let homeURL = URL(string: "https://wiki.yandex.ru/sd-portal/it-support/it-support-office/")!

    /// Домены, по которым пользователь может свободно ходить. Разрешены и все их поддомены.
    static let allowedDomains: Set<String> = [
        "yandex.ru",
        "auth.cloud.yandex.com",
        "sso.ya.ru",
        "lamoda.ru",
        "lamoda.tech",
    ]

    /// Страницы входа: Yandex Cloud → Яндекс ID → корпоративный ADFS. На них работает автовход
    /// и не срабатывает возврат по бездействию, чтобы администратор успел ввести код 2FA.
    static let authHosts: Set<String> = [
        "auth.cloud.yandex.ru",
        "auth.cloud.yandex.com",
        "passport.yandex.ru",
        "sso.passport.yandex.ru",
        "sso.yandex.ru",
        "sso.ya.ru",
        "sso.lamoda.ru",
    ]

    static let idleTimeout: TimeInterval = 30

    /// Меню администратора: долгое нажатие на кнопку «Домой» + PIN. Обязательно смените PIN.
    static let adminPIN = "111111"
    static let adminLongPressDuration: TimeInterval = 5

    /// Защита от блокировки учётки: не больше N отправок пароля и кода 2FA за окно времени.
    static let maxLoginSubmissions = 6
    static let loginSubmissionWindow: TimeInterval = 300

    static func isAllowedHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return allowedDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func isAuthHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return authHosts.contains(host)
    }
}
