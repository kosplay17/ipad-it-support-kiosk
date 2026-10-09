import UIKit
import WebKit
import os

final class KioskViewController: UIViewController {
    private let log = Logger(subsystem: "ITSupportKiosk", category: "kiosk")

    private var webView: WKWebView!
    private let homeButton = UIButton(type: .custom)
    private let toastLabel = ToastLabel()

    private var idleTimer: Timer?
    private var toastTimer: Timer?
    private var retryWorkItem: DispatchWorkItem?
    private var passwordSubmissions: [Date] = []

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setUpWebView()
        setUpHomeButton()
        setUpToast()
        setUpActivityRecognizer()
        loadHome()
    }

    // MARK: - Setup

    private func setUpWebView() {
        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: Scripts.activityTracker,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        contentController.addUserScript(WKUserScript(
            source: Scripts.disableCallout,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        let handler = WeakScriptMessageHandler(self)
        contentController.add(handler, name: Scripts.activityHandler)
        contentController.add(handler, name: Scripts.loginHandler)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.dataDetectorTypes = []
        configuration.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setUpHomeButton() {
        let symbol = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        homeButton.setImage(UIImage(systemName: "house.fill", withConfiguration: symbol), for: .normal)
        homeButton.tintColor = .white
        homeButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
        homeButton.layer.cornerRadius = 36
        homeButton.layer.shadowColor = UIColor.black.cgColor
        homeButton.layer.shadowOpacity = 0.25
        homeButton.layer.shadowRadius = 8
        homeButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        homeButton.accessibilityLabel = "На главную"
        homeButton.addTarget(self, action: #selector(homeTapped), for: .touchUpInside)

        let adminPress = UILongPressGestureRecognizer(target: self, action: #selector(adminPressRecognized(_:)))
        adminPress.minimumPressDuration = KioskConfig.adminLongPressDuration
        homeButton.addGestureRecognizer(adminPress)

        homeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(homeButton)
        NSLayoutConstraint.activate([
            homeButton.widthAnchor.constraint(equalToConstant: 72),
            homeButton.heightAnchor.constraint(equalToConstant: 72),
            homeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            homeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    private func setUpToast() {
        toastLabel.font = .systemFont(ofSize: 17, weight: .medium)
        toastLabel.textColor = .white
        toastLabel.textAlignment = .center
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        toastLabel.layer.cornerRadius = 12
        toastLabel.clipsToBounds = true
        toastLabel.alpha = 0
        toastLabel.isUserInteractionEnabled = false
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toastLabel)
        NSLayoutConstraint.activate([
            toastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            toastLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48),
        ])
    }

    private func setUpActivityRecognizer() {
        let recognizer = ActivityGestureRecognizer { [weak self] in
            self?.registerActivity()
        }
        recognizer.delegate = self
        view.addGestureRecognizer(recognizer)
    }

    // MARK: - Navigation

    private func loadHome() {
        retryWorkItem?.cancel()
        view.endEditing(true)
        webView.load(URLRequest(url: KioskConfig.homeURL))
    }

    @objc private func homeTapped() {
        loadHome()
    }

    private func isHome(_ url: URL?) -> Bool {
        guard let url else { return false }
        let home = KioskConfig.homeURL
        return url.host?.lowercased() == home.host?.lowercased() && url.path == home.path
    }

    private func isAllowedMainFrameNavigation(to url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "about":
            return url.absoluteString == "about:blank"
        case "http", "https":
            return KioskConfig.isAllowedHost(url.host)
        default:
            return false
        }
    }

    // MARK: - Idle timeout

    private func registerActivity() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: KioskConfig.idleTimeout, repeats: false) { [weak self] _ in
            self?.idleTimeoutFired()
        }
    }

    private func idleTimeoutFired() {
        // Не сбрасываем, пока открыто меню администратора или идёт вход в Яндекс ID.
        if presentedViewController != nil || KioskConfig.isAuthHost(webView.url?.host) {
            registerActivity()
            return
        }
        loadHome()
    }

    // MARK: - Auto login

    private func runAutoLoginIfNeeded() {
        guard let credentials = CredentialsStore.load() else {
            showToast("Автовход не настроен: задайте логин и пароль в меню администратора")
            return
        }

        let now = Date()
        passwordSubmissions.removeAll { now.timeIntervalSince($0) > KioskConfig.passwordSubmissionWindow }
        guard passwordSubmissions.count < KioskConfig.maxPasswordSubmissions else {
            showToast("Автовход приостановлен: несколько неудачных попыток подряд")
            return
        }

        let script = Scripts.autoLogin(credentials, allowedHosts: KioskConfig.authHosts)
        webView.evaluateJavaScript(script) { [log] _, error in
            if let error {
                log.error("Auto login script failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Errors

    private func handleLoadError(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        // 102: загрузка прервана политикой навигации (мы сами её отменили).
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }

        log.error("Load failed: \(nsError.localizedDescription, privacy: .public)")
        showToast("Нет соединения. Повторная попытка через 10 секунд")

        retryWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.loadHome() }
        retryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    // MARK: - Toast

    private func showToast(_ text: String) {
        toastLabel.text = text
        toastTimer?.invalidate()
        UIView.animate(withDuration: 0.2) { self.toastLabel.alpha = 1 }
        toastTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.3) { self?.toastLabel.alpha = 0 }
        }
    }

    // MARK: - Admin menu

    @objc private func adminPressRecognized(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, presentedViewController == nil else { return }

        let alert = UIAlertController(title: "Администрирование", message: "Введите PIN", preferredStyle: .alert)
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Войти", style: .default) { [weak self, weak alert] _ in
            guard alert?.textFields?.first?.text == KioskConfig.adminPIN else { return }
            self?.showAdminMenu()
        })
        present(alert, animated: true)
    }

    private func showAdminMenu() {
        let login = CredentialsStore.load()?.login ?? "не задана"
        let currentURL = webView.url?.absoluteString ?? "—"
        let menu = UIAlertController(
            title: "Администрирование",
            message: "Учётная запись: \(login)\nТекущий адрес: \(currentURL)",
            preferredStyle: .alert
        )
        menu.addAction(UIAlertAction(title: "Задать логин и пароль Яндекс ID", style: .default) { [weak self] _ in
            self?.showCredentialsForm()
        })
        menu.addAction(UIAlertAction(title: "Перезагрузить главную", style: .default) { [weak self] _ in
            self?.loadHome()
        })
        if UIAccessibility.isGuidedAccessEnabled {
            menu.addAction(UIAlertAction(title: "Снять блокировку приложения", style: .default) { _ in
                UIAccessibility.requestGuidedAccessSession(enabled: false) { _ in }
            })
        }
        menu.addAction(UIAlertAction(title: "Выйти из аккаунта и очистить данные", style: .destructive) { [weak self] _ in
            self?.resetWebsiteData()
        })
        menu.addAction(UIAlertAction(title: "Удалить сохранённые логин и пароль", style: .destructive) { [weak self] _ in
            CredentialsStore.clear()
            self?.showToast("Логин и пароль удалены")
        })
        menu.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
        present(menu, animated: true)
    }

    private func showCredentialsForm() {
        let form = UIAlertController(
            title: "Яндекс ID",
            message: "Сервисная учётная запись для автоматического входа",
            preferredStyle: .alert
        )
        form.addTextField { field in
            field.placeholder = "Логин"
            field.text = CredentialsStore.load()?.login
            field.keyboardType = .emailAddress
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        form.addTextField { field in
            field.placeholder = "Пароль"
            field.isSecureTextEntry = true
        }
        form.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        form.addAction(UIAlertAction(title: "Сохранить", style: .default) { [weak self, weak form] _ in
            guard let fields = form?.textFields, fields.count == 2 else { return }
            let login = (fields[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let password = fields[1].text ?? ""
            guard !login.isEmpty, !password.isEmpty else { return }

            CredentialsStore.save(Credentials(login: login, password: password))
            self?.passwordSubmissions.removeAll()
            self?.showToast("Учётные данные сохранены")
            self?.loadHome()
        })
        present(form, animated: true)
    }

    private func resetWebsiteData() {
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            self?.passwordSubmissions.removeAll()
            self?.loadHome()
        }
    }
}

// MARK: - WKNavigationDelegate

extension KioskViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if !isMainFrame {
            // Встроенные во фрейм формы, капча и т.п. Из фрейма нельзя уйти со страницы,
            // а попытки открыть новое окно проверяются ниже как навигация главного фрейма.
            let scheme = url.scheme?.lowercased() ?? ""
            decisionHandler(["http", "https", "about", "data", "blob"].contains(scheme) ? .allow : .cancel)
            return
        }

        if isAllowedMainFrameNavigation(to: url) {
            decisionHandler(.allow)
            return
        }

        log.info("Blocked: \(url.absoluteString, privacy: .public)")
        if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
            showToast("Этот адрес недоступен в киоске")
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if KioskConfig.isAuthHost(webView.url?.host) {
            runAutoLoginIfNeeded()
        } else if !isHome(webView.url) {
            registerActivity()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadError(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadHome()
    }
}

// MARK: - WKUIDelegate

extension KioskViewController: WKUIDelegate {
    /// target="_blank" и window.open открываем в этом же окне, если адрес разрешён.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url,
           isAllowedMainFrameNavigation(to: url) {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

// MARK: - WKScriptMessageHandler

extension KioskViewController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case Scripts.activityHandler:
            registerActivity()
        case Scripts.loginHandler:
            passwordSubmissions.append(Date())
        default:
            break
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension KioskViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
