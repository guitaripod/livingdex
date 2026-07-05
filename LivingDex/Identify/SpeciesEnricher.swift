import Foundation

/// Real, grounded context for a captured species from the Living Dex domain
/// Worker: a rarity tier computed from GBIF occurrence density near the sighting,
/// plus a short Wikipedia summary used to ground narration. Best-effort — a
/// timeout or failure leaves the on-device candidate's own values intact.
struct SpeciesEnrichment: Sendable {
    var rarity: Rarity
    var scientificName: String?
    var commonName: String?
    var summary: String?
    var iucnCategory: String?
}

/// The outcome of asking the worker to ground a candidate against GBIF.
/// The distinction matters for correctness: `unresolved` means GBIF actively
/// rejected the name (a likely hallucination — must NOT be minted), while
/// `unavailable` means we couldn't reach the service (offline/timeout — mint
/// provisionally and heal on a later card open).
enum EnrichmentResult: Sendable {
    case resolved(SpeciesEnrichment)
    case unresolved
    case unavailable
}

final class SpeciesEnricher: Sendable {
    static let shared = SpeciesEnricher()

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = Secrets.workerBaseURL, timeout: TimeInterval = 3.5) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    func enrich(candidate: SpeciesCandidate, context: CaptureContext) async -> EnrichmentResult {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("v1/enrich"), resolvingAgainstBaseURL: false) else {
            return .unavailable
        }
        var items = [URLQueryItem(name: "name", value: candidate.scientificName)]
        if let key = Self.gbifKey(from: candidate.speciesId) {
            items.append(URLQueryItem(name: "taxonKey", value: key))
        }
        if let lat = context.latitude, let lng = context.longitude {
            items.append(URLQueryItem(name: "lat", value: String(lat)))
            items.append(URLQueryItem(name: "lng", value: String(lng)))
        }
        components.queryItems = items
        guard let url = components.url else { return .unavailable }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return .unavailable }
            if http.statusCode == 404 {
                AppLogger.shared.warn("enrich unresolved: \(candidate.scientificName)", category: .identify)
                return .unresolved
            }
            guard http.statusCode == 200 else { return .unavailable }
            let decoded = try JSONDecoder().decode(EnrichResponse.self, from: data)
            guard let rarity = Rarity(rawValue: decoded.rarity) else { return .unavailable }
            AppLogger.shared.info("enriched \(candidate.commonName) -> \(rarity.rawValue)", category: .identify)
            return .resolved(SpeciesEnrichment(
                rarity: rarity,
                scientificName: decoded.factSheet.scientificName,
                commonName: decoded.factSheet.commonName,
                summary: decoded.factSheet.summary,
                iucnCategory: decoded.factSheet.iucnCategory))
        } catch {
            AppLogger.shared.warn("enrich failed: \(error.localizedDescription)", category: .identify)
            return .unavailable
        }
    }

    static func gbifKey(from speciesId: String) -> String? {
        guard speciesId.hasPrefix("gbif:") else { return nil }
        return String(speciesId.dropFirst("gbif:".count))
    }

    private struct EnrichResponse: Decodable {
        var rarity: String
        var factSheet: FactSheet
        struct FactSheet: Decodable {
            var scientificName: String?
            var commonName: String?
            var summary: String?
            var iucnCategory: String?
        }
    }
}
