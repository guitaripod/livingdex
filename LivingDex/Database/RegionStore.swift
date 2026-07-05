import Foundation

/// A species that plausibly occurs near the player — a slot in the Regional Dex.
struct RegionSpecies: Codable, Hashable, Sendable {
    var speciesId: String
    var commonName: String?
    var scientificName: String
    var realm: Realm
    var rarity: Rarity

    var displayName: String { commonName ?? scientificName }
}

/// Fetches and caches the Regional Dex (the local target species list from the
/// domain Worker's `/v1/region`). Cached per coarse location so it isn't refetched
/// as the player moves a little; the list is stable for an area.
final class RegionStore: @unchecked Sendable {
    static let shared = RegionStore()

    private let baseURL: URL
    private let session: URLSession
    private var cache: [String: [RegionSpecies]] = [:]
    private let lock = NSLock()

    init(baseURL: URL = Secrets.workerBaseURL, timeout: TimeInterval = 8) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
    }

    /// Coarse cache key (~0.5° cells) so nearby fetches share a result.
    private func key(_ lat: Double, _ lng: Double) -> String {
        "\(Int((lat * 2).rounded())),\(Int((lng * 2).rounded()))"
    }

    /// Regional species list, or nil if the fetch failed (network/timeout) — the
    /// caller distinguishes that from a genuine empty region so it can offer retry.
    func regionalSpecies(latitude: Double, longitude: Double) async -> [RegionSpecies]? {
        let k = key(latitude, longitude)
        if let hit = lock.withLock({ cache[k] }) { return hit }

        guard var components = URLComponents(url: baseURL.appendingPathComponent("v1/region"), resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lng", value: String(longitude)),
            URLQueryItem(name: "limit", value: "120"),
        ]
        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(RegionResponse.self, from: data)
            let species = decoded.species.map {
                RegionSpecies(
                    speciesId: "gbif:\($0.taxonKey)", commonName: $0.commonName,
                    scientificName: $0.scientificName, realm: Realm(rawValue: $0.realm) ?? .other,
                    rarity: Rarity(rawValue: $0.rarity) ?? .common)
            }
            lock.withLock { cache[k] = species }
            AppLogger.shared.info("regional dex: \(species.count) species", category: .identify)
            return species
        } catch {
            AppLogger.shared.warn("region fetch failed: \(error.localizedDescription)", category: .identify)
            return nil
        }
    }

    private struct RegionResponse: Decodable {
        var species: [Item]
        struct Item: Decodable {
            var taxonKey: Int
            var commonName: String?
            var scientificName: String
            var realm: String
            var rarity: String
        }
    }
}
