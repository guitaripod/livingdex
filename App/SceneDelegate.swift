import MidgarCore
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        CreditsModel.shared.start()

        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = AppSettings.appearance
        window.tintColor = DesignSystem.Color.accent
        window.rootViewController = Self.makeRoot()
        self.window = window
        window.makeKeyAndVisible()

        _ = ProAccess.shared
        // Game Center auth is deferred to the first non-Field tab (see
        // RootViewController) so its foreground-steal never freezes the camera at launch.
        MidgarLog.info("scene connected", category: .app)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        LocationProvider.shared.warmUp()
        Task { await CreditsModel.shared.refresh() }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        LocationProvider.shared.stopUpdates()
    }

    /// Returns the app to its first-launch screen — used after account deletion so the
    /// player lands on a clean onboarding with nothing left behind.
    func presentFirstRun() {
        guard let window else { return }
        UIView.transition(with: window, duration: 0.4, options: .transitionCrossDissolve) {
            window.rootViewController = Self.makeRoot()
        }
    }

    private static func makeRoot() -> UIViewController {
        #if DEBUG
        if DemoSeeder.isEnabled {
            if DemoSeeder.route == "onboarding" { return OnboardingViewController() }
            let root = RootViewController()
            switch DemoSeeder.route {
            case "profile", "paywall": root.selectedIndex = 2
            case "dex", "card", "caught", "nearby", "reveal": root.selectedIndex = 1
            default: root.selectedIndex = 0
            }
            return root
        }
        #endif
        guard AppSettings.hasOnboarded else {
            let onboarding = OnboardingViewController()
            onboarding.onFinish = { [weak onboarding] in
                AppSettings.hasOnboarded = true
                guard let window = onboarding?.view.window else { return }
                UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
                    window.rootViewController = RootViewController()
                }
            }
            return onboarding
        }
        return RootViewController()
    }
}
