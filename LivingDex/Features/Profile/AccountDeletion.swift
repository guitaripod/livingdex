import AICreditsCore
import Foundation

enum AccountDeletionError: Error, Equatable {
    case offline
    case server
}

/// Removes the player's server-side account (credit wallet, ledger, stored images).
protocol RemoteAccountDeleting: Sendable {
    func deleteRemoteAccount() async throws
}

/// `DELETE /v1/identity` on the mako credits backend, authenticated by the
/// player's own API key. A key the server no longer recognises (401/404) counts as
/// already deleted; only an unreachable or failing server blocks deletion.
struct MakoAccountDeleter: RemoteAccountDeleting {
    let baseURL: URL
    let appID: String
    let apiKey: @Sendable () async -> String?
    let session: URLSession

    init(
        baseURL: URL = Secrets.makoBaseURL,
        appID: String = "livingdex",
        session: URLSession = .shared,
        apiKey: @escaping @Sendable () async -> String?
    ) {
        self.baseURL = baseURL
        self.appID = appID
        self.session = session
        self.apiKey = apiKey
    }

    func deleteRemoteAccount() async throws {
        guard let key = await apiKey() else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/identity"))
        request.httpMethod = "DELETE"
        request.timeoutInterval = 20
        request.setValue(appID, forHTTPHeaderField: "X-App-ID")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AccountDeletionError.server }
            switch http.statusCode {
            case 200...299, 401, 404: return
            default: throw AccountDeletionError.server
            }
        } catch let error as AccountDeletionError {
            throw error
        } catch {
            throw AccountDeletionError.offline
        }
    }
}

/// Permanently deletes everything Living Dex holds about the player: the remote
/// account first (so a failure leaves the device untouched and retryable), then the
/// local credentials, collection, photos, progress and caches.
struct AccountDeletionService: Sendable {
    let remote: any RemoteAccountDeleting
    let signOut: @Sendable () async -> Void
    let eraseLocal: @Sendable () throws -> Void

    func deleteEverything() async throws {
        try await remote.deleteRemoteAccount()
        await signOut()
        try eraseLocal()
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
