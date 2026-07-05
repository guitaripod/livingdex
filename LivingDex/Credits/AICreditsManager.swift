import Foundation
import AICreditsCore
import AICreditsRevenueCat
import AICreditsUI

/// Wires the shared mako AI-credits backend (X-App-ID `livingdex`) through the
/// AICredits package. The `pro` entitlement unlocks unlimited Claude cloud ID +
/// "ask the creature" Q&A; consumable credit packs meter per-cloud-call cost for
/// non-subscribers. On-device identification & narration stay free of this.
final class AICreditsManager: Sendable {
    static let shared = AICreditsManager()

    @MainActor static let store = AICreditsStore(
        client: AICreditsManager.shared.client, lowBalanceThreshold: 5)

    let client: AICreditsClient
    let baseURL = Secrets.makoBaseURL
    private let appID = "livingdex"
    private let revenueCatPublicKey = Secrets.revenueCatPublicKey

    private init() {
        let config = AICreditsConfig(baseURL: baseURL, appID: appID, lowBalanceThreshold: 5)
        client = AICreditsClient(
            config: config,
            purchaseProvider: RevenueCatPurchaseProvider(apiKey: revenueCatPublicKey))
    }
}
