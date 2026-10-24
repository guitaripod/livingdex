import MidgarCore
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        LivingDexMidgar.configureLogging()
        LivingDexMidgar.shared.start()
        ReviewPrompt.beginSession()
        _ = DatabaseManager.shared
        #if DEBUG
        DemoSeeder.seedIfNeeded()
        #endif
        MidgarLog.info("app launched", category: .app)
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
