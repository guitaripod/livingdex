import Foundation
import AICreditsCore

/// The AI calls of the app, metered by mako against the Midgar ID's wallet (X-App-ID `livingdex`). AICredits only runs
/// the capability calls here: its purchase provider cannot buy, because the credit packs and Pro are sold by
/// MidgarStore and MidgarCredits. The `pro` entitlement unlocks unlimited Claude cloud ID and "ask the creature" Q&A,
/// which mako checks itself; consumable credit packs meter per-cloud-call cost for non-subscribers. On-device
/// identification and narration stay free of this. Calls go to mako behind the gateway and carry the Midgar token next
/// to the api key.
final class AICreditsManager: Sendable {
    static let shared = AICreditsManager()

    let client: AICreditsClient
    let baseURL = LivingDexMidgar.intelligenceURL
    private let appID = LivingDexMidgar.tenantID

    private init() {
        let config = AICreditsConfig(
            baseURL: baseURL, appID: appID, lowBalanceThreshold: 5,
            additionalHeaders: { await LivingDexMidgar.shared.midgarTokenHeaders() })
        client = AICreditsClient(config: config, purchaseProvider: HostManagedPurchaseProvider())
    }

    /// The api key of the old per-app account, which MidgarCredits sends as its legacy key so mako links the balance
    /// from before the move to the Midgar ID's wallet. The key lives in the keychain; a device that has none yet gets
    /// its account registered here, the same one the first AI call would register. Nil when that fails.
    func legacyAPIKey() async -> String? {
        try? await client.bootstrap().apiKey
    }
}

/// The purchase provider the AICredits client needs but never uses: it sells nothing, and every purchase attempt fails.
private nonisolated struct HostManagedPurchaseProvider: PurchaseProvider {
    func configure(appUserID: String) async {}
    func availablePackages() async throws -> [StorePackage] { [] }
    func purchase(packageID: String) async throws -> PurchaseReceipt {
        throw AICreditsError.purchaseFailed("Purchases are handled by the host app.")
    }
    func restore() async throws -> [RestoredEntitlement] { [] }
    func alias(to newAppUserID: String) async {}
}
