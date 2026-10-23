import Foundation
import MidgarCore

/// The calls Living Dex makes to mako and to its own worker through the Midgar gateway: `/v1/intelligence/` for mako
/// and `/v1/livingdex/` for the worker. mako validates the caller by its api key in `Authorization`; the worker is
/// keyless and the gateway forwards no credential to it, so worker calls carry none.
nonisolated struct LivingDexGateway: Sendable {
    static let workerService = "livingdex"
    static let makoService = "intelligence"

    private let client: MidgarHTTPClient

    init(client: MidgarHTTPClient) {
        self.client = client
    }

    /// Sends a call once and returns the 2xx body. Throws the client's error for any other status. A repeat is never
    /// sent by the transport: the worker calls are advisory and must degrade within their short timeout, and the
    /// account deletion must not be mistaken for a second one.
    @discardableResult
    func send(
        _ method: MidgarHTTPMethod,
        service: String,
        path: String,
        query: [URLQueryItem] = [],
        apiKey: String? = nil
    ) async throws(MidgarHTTPError) -> Data {
        var headers: [String: String] = [:]
        if let apiKey { headers["Authorization"] = "Bearer \(apiKey)" }
        let request = MidgarRequest(
            service: service, path: path, method: method, query: query, headers: headers, neverRetries: true)
        return try await client.sendRaw(request).0
    }

    /// A GET on the worker.
    func fetchFromWorker(_ path: String, query: [URLQueryItem]) async throws(MidgarHTTPError) -> Data {
        try await send(.get, service: Self.workerService, path: path, query: query)
    }
}
