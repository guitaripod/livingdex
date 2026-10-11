import UIKit

/// Lightweight user-defaults-backed preferences.
enum AppSettings {
    private static var defaults: UserDefaults { .standard }

    private enum Key {
        static let hasOnboarded = "hasOnboarded"
        static let appearance = "appearance"
        static let hasAcceptedCloudAI = "hasAcceptedCloudAI"
        static let sampleCursor = "sampleCursor"
        static let all = [hasOnboarded, appearance, hasAcceptedCloudAI, sampleCursor]
    }

    static var hasOnboarded: Bool {
        get { defaults.bool(forKey: Key.hasOnboarded) }
        set { defaults.set(newValue, forKey: Key.hasOnboarded) }
    }

    /// Whether the player agreed to send photos to the cloud identification service.
    /// Asked once, just before the first photo would leave the device.
    static var hasAcceptedCloudAI: Bool {
        get { defaults.bool(forKey: Key.hasAcceptedCloudAI) }
        set { defaults.set(newValue, forKey: Key.hasAcceptedCloudAI) }
    }

    /// Position in the bundled sample-photo rotation, so each "Try a sample photo"
    /// tap shows a different creature before repeating.
    static var sampleCursor: Int {
        get { defaults.integer(forKey: Key.sampleCursor) }
        set { defaults.set(newValue, forKey: Key.sampleCursor) }
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

    /// Returns every preference to its first-launch value — used by account deletion.
    static func reset() {
        Key.all.forEach { defaults.removeObject(forKey: $0) }
        applyAppearance()
    }
}
