import AICreditsCore
import Foundation
import MidgarCredits

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

/// Deletes the old per-app account at mako. With the wallet, the key goes through `MidgarCredits.deleteLegacyAccount()`
/// (`DELETE /v1/identity` authorized by the player's own API key, which also erases this app's partition of the wallet for
/// a player already linked to it); a key mako no longer recognises, or an account it no longer has, counts as already
/// deleted. Without the wallet (a host that reaches no Midgar service) AICredits deletes its own identity. An unreachable
/// or failing server blocks deletion so the key is never discarded while the account may still exist.
struct LegacyAccountDeleter: RemoteAccountDeleting {
    let credits: MidgarCredits?
    let client: AICreditsClient

    func deleteRemoteAccount() async throws {
        do {
            if let credits {
                try await credits.deleteLegacyAccount()
            } else {
                try await client.deleteIdentity()
            }
        } catch {
            throw Self.accountDeletionError(for: error)
        }
    }

    /// A call that never got an answer is offline, so the player can retry; any answer that is not a success is a
    /// server failure.
    static func accountDeletionError(for error: any Error) -> AccountDeletionError {
        switch error {
        case MidgarCreditsError.offline:
            return .offline
        case AICreditsError.transport:
            return .offline
        default:
            return .server
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
            remote: LegacyAccountDeleter(credits: LivingDexMidgar.shared.credits, client: client),
            signOut: { await client.signOut() },
            eraseLocal: {
                try DatabaseManager.shared.eraseAllData()
                RegionStore.shared.clear()
            })
    }
}
