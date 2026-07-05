import Combine
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var creditsObservers: Set<AnyCancellable> = []

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        observeCreditsEvents()

        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = .dark
        window.tintColor = DesignSystem.Color.accent
        window.rootViewController = Self.makeRoot()
        self.window = window
        window.makeKeyAndVisible()

        Task { await AICreditsManager.store.bootstrap() }
        GameCenterService.shared.authenticate()
        AppLogger.shared.info("scene connected", category: .app)
    }

    private static func makeRoot() -> UIViewController {
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

    /// The AICredits package emits no logging of its own, so the store's
    /// published identity/error/balance transitions are the app's only trace of
    /// bootstrap, Apple-link, refresh, and purchase outcomes.
    private func observeCreditsEvents() {
        let store = AICreditsManager.store
        store.$identity
            .compactMap { $0 }
            .removeDuplicates()
            .sink { AppLogger.shared.info("credits identity \($0.kind.rawValue) \($0.userID.prefix(8))", category: .credits) }
            .store(in: &creditsObservers)
        store.$error
            .compactMap { $0 }
            .sink { AppLogger.shared.error("credits error: \($0.localizedDescription)", category: .credits) }
            .store(in: &creditsObservers)
        store.$balance
            .removeDuplicates()
            .dropFirst()
            .sink { AppLogger.shared.info("credits balance \($0)", category: .credits) }
            .store(in: &creditsObservers)
    }
}
