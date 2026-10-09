import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = KioskViewController()
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        UIApplication.shared.isIdleTimerDisabled = true

        // Сработает только на supervised-iPad, если MDM разрешил этому приложению
        // Autonomous Single App Mode. В остальных случаях вызов ничего не делает.
        if !UIAccessibility.isGuidedAccessEnabled {
            UIAccessibility.requestGuidedAccessSession(enabled: true) { _ in }
        }
    }
}
