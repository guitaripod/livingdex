import Foundation

/// Lightweight user-defaults-backed preferences.
enum AppSettings {
    private static var defaults: UserDefaults { .standard }

    private enum Key {
        static let hasOnboarded = "hasOnboarded"
    }

    static var hasOnboarded: Bool {
        get { defaults.bool(forKey: Key.hasOnboarded) }
        set { defaults.set(newValue, forKey: Key.hasOnboarded) }
    }
}
