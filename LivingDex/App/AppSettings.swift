import UIKit

/// Lightweight user-defaults-backed preferences.
enum AppSettings {
    private static var defaults: UserDefaults { .standard }

    private enum Key {
        static let hasOnboarded = "hasOnboarded"
        static let appearance = "appearance"
    }

    static var hasOnboarded: Bool {
        get { defaults.bool(forKey: Key.hasOnboarded) }
        set { defaults.set(newValue, forKey: Key.hasOnboarded) }
    }

    /// User's appearance choice; defaults to following the system.
    static var appearance: UIUserInterfaceStyle {
        get { UIUserInterfaceStyle(rawValue: defaults.integer(forKey: Key.appearance)) ?? .unspecified }
        set {
            defaults.set(newValue.rawValue, forKey: Key.appearance)
            applyAppearance()
        }
    }

    /// Applies the chosen appearance to every connected window.
    static func applyAppearance() {
        let style = appearance
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
