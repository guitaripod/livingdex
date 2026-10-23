import AICreditsCore
import Foundation
import MidgarCore

enum AccountDeletionError: Error, Equatable {
    case offline
    case server
    case localCleanup
}

extension AccountDeletionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .offline: return "You appear to be offline. Nothing was deleted, so reconnect and try again."
        case .server: return "Something went wrong on our side. Nothing was deleted, so try again in a moment."
        case .localCleanup: return "Some data couldn't be removed from this device. Deleting the app removes the rest."
        }
    }
}

/// Removes the player's server-side account (credit wallet, ledger, stored images).
protocol RemoteAccountDeleting: Sendable {
    func deleteRemoteAccount() async throws
}

/// `DELETE /v1/identity` on the mako credits backend behind the Midgar gateway, authenticated by the
/// player's own API key. A key the server no longer recognises (401) counts as already
/// deleted; an unreachable or failing server — including a missing endpoint (404) —
/// blocks deletion so the key is never discarded while the account may still exist.
struct MakoAccountDeleter: RemoteAccountDeleting {
    let gateway: LivingDexGateway
    let apiKey: @Sendable () async -> String?

    init(
        gateway: LivingDexGateway = LivingDexMidgar.makoGateway(),
        apiKey: @escaping @Sendable () async -> String?
    ) {
        self.gateway = gateway
        self.apiKey = apiKey
    }

    func deleteRemoteAccount() async throws {
        guard let key = await apiKey() else { return }
        do throws(MidgarHTTPError) {
            try await gateway.send(.delete, service: LivingDexGateway.makoService, path: "v1/identity", apiKey: key)
        } catch {
            try Self.acceptOrThrow(error)
        }
    }

    /// An unknown key is already deleted. A call that never got an answer is offline, so the player can retry; any
    /// answer that is not a success is a server failure.
    private static func acceptOrThrow(_ error: MidgarHTTPError) throws {
        switch error {
        case .unauthorized:
            return
        case .offline, .timeout, .cancelled, .tokenUnavailable:
            throw AccountDeletionError.offline
        default:
            throw AccountDeletionError.server
        }
    }
}

/// Permanently deletes everything Living Dex holds about the player: the remote
/// account first (so a failure leaves the device untouched and retryable), then the
/// local credentials, collection, photos, progress and caches. A local failure after the
/// remote account is gone is reported as ``AccountDeletionError/localCleanup``.
struct AccountDeletionService: Sendable {
    let remote: any RemoteAccountDeleting
    let signOut: @Sendable () async -> Void
    let eraseLocal: @Sendable () throws -> Void

    func deleteEverything() async throws {
        try await remote.deleteRemoteAccount()
        await signOut()
        do {
            try eraseLocal()
        } catch {
            throw AccountDeletionError.localCleanup
        }
    }

    static func live() -> AccountDeletionService {
        let client = AICreditsManager.shared.client
        return AccountDeletionService(
            remote: MakoAccountDeleter(apiKey: { await client.identity?.apiKey }),
            signOut: { await client.signOut() },
            eraseLocal: {
                try DatabaseManager.shared.eraseAllData()
                RegionStore.shared.clear()
            })
    }
}
