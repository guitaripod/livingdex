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
/// domain Worker's `/v1/region`). Cached per coarse location cell so it isn't
/// refetched as the player moves a little; the list is stable for an area. The
/// cache is persisted to disk with a staleness window, so a cold launch (or an
/// offline outdoors session) renders the last-known list immediately instead of
/// spinning on the network.
final class RegionStore: @unchecked Sendable {
    static let shared = RegionStore()

    private let baseURL: URL
    private let session: URLSession
    private let ttl: TimeInterval
    private var cache: [String: CacheEntry] = [:]
    private var refreshing: Set<String> = []
    private var loadedFromDisk = false
    private let lock = NSLock()

    init(baseURL: URL = Secrets.workerBaseURL, timeout: TimeInterval = 8, staleAfter: TimeInterval = 24 * 60 * 60) {
        self.baseURL = baseURL
        self.ttl = staleAfter
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.requestCachePolicy = .useProtocolCachePolicy
        self.session = URLSession(configuration: config)
    }

    /// Coarse cache key (~0.5° cells) so nearby fetches share a result.
    private func key(_ lat: Double, _ lng: Double) -> String {
        "\(Int((lat * 2).rounded())),\(Int((lng * 2).rounded()))"
    }

    /// The center of the ~0.5° cell a coordinate falls in. Requesting the cell
    /// center (not the raw GPS fix) makes the URL stable across launches and GPS
    /// jitter, so URLCache and the edge cache actually hit.
    private func cellCenter(_ value: Double) -> Double {
        (value * 2).rounded() / 2
    }

    /// Regional species list. Returns persisted data immediately when available
    /// (refreshing in the background if stale), fetches when nothing is cached,
    /// and returns nil only when there is no persisted data *and* the fetch fails —
    /// so the caller can still distinguish an empty region from a failed one.
    func regionalSpecies(latitude: Double, longitude: Double) async -> [RegionSpecies]? {
        let k = key(latitude, longitude)
        let cellLat = cellCenter(latitude)
        let cellLng = cellCenter(longitude)

        let cached: CacheEntry? = lock.withLock {
            loadDiskIfNeeded()
            return cache[k]
        }

        if let cached {
            if Date().timeIntervalSince(cached.fetchedAt) >= ttl {
                refreshInBackground(key: k, lat: cellLat, lng: cellLng)
            }
            return cached.species
        }

        return await fetchAndStore(key: k, lat: cellLat, lng: cellLng)
    }

    private func refreshInBackground(key: String, lat: Double, lng: Double) {
        let shouldStart = lock.withLock { () -> Bool in
            guard !refreshing.contains(key) else { return false }
            refreshing.insert(key)
            return true
        }
        guard shouldStart else { return }
        Task.detached { [weak self] in
            guard let self else { return }
            _ = await self.fetchAndStore(key: key, lat: lat, lng: lng)
            self.lock.withLock { _ = self.refreshing.remove(key) }
        }
    }

    private func fetchAndStore(key k: String, lat: Double, lng: Double) async -> [RegionSpecies]? {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("v1/region"), resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
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
            lock.withLock {
                cache[k] = CacheEntry(species: species, fetchedAt: Date())
                persist()
            }
            AppLogger.shared.info("regional dex: \(species.count) species", category: .identify)
            return species
        } catch {
            AppLogger.shared.warn("region fetch failed: \(error.localizedDescription)", category: .identify)
            return nil
        }
    }

    // MARK: Persistence

    private struct CacheEntry: Codable {
        var species: [RegionSpecies]
        var fetchedAt: Date
    }

    private func cacheFileURL() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        else { return nil }
        return support.appendingPathComponent("region-cache.json")
    }

    /// Loads the persisted cell cache once, lazily. Caller must hold `lock`.
    private func loadDiskIfNeeded() {
        guard !loadedFromDisk else { return }
        loadedFromDisk = true
        guard let url = cacheFileURL(), let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else { return }
        cache = decoded
    }

    /// Writes the whole cell cache to disk. Caller must hold `lock`.
    private func persist() {
        guard let url = cacheFileURL(), let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
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
