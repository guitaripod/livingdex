import Foundation

/// Copy to `Secrets.swift` (gitignored) and fill in. `Secrets.swift` is excluded
/// from the build when absent and injected by CI.
enum Secrets {
    /// Shared AI-credits backend (identity, credits ledger, RevenueCat, AI run).
    static let makoBaseURL = URL(string: "https://mako.midgarcorp.cc")!

    /// RevenueCat public SDK key for the `livingdex` app.
    static let revenueCatPublicKey = "appl_XXXXXXXXXXXXXXXXXXXXXXXXXX"

    /// Living Dex domain Worker (real rarity + fact-sheets from GBIF/Wikipedia).
    static let workerBaseURL = URL(string: "https://livingdex-worker.guitaripod.workers.dev")!
}
