import Foundation

/// Copy to `Secrets.swift` (gitignored) and fill in. `Secrets.swift` is excluded
/// from the build when absent and injected by CI.
/// Service addresses are not secrets: mako and Living Dex's worker are reached through the Midgar gateway,
/// whose address lives in `LivingDexMidgar`.
enum Secrets {
    /// RevenueCat public SDK key for the `livingdex` app.
    static let revenueCatPublicKey = "appl_XXXXXXXXXXXXXXXXXXXXXXXXXX"
}
