import Foundation

/// Real, grounded context for a captured species from the Living Dex domain
/// Worker: a rarity tier computed from GBIF occurrence density near the sighting,
/// plus a short Wikipedia summary used to ground narration. Best-effort — a
/// timeout or failure leaves the on-device candidate's own values intact.
struct SpeciesEnrichment: Sendable {
    var rarity: Rarity
    /// GBIF taxon key of the confirmed species, when the Worker resolved one. Lets
    /// a cloud "sci:" capture adopt the canonical "gbif:<taxonKey>" id so it fills
    /// its (gbif-keyed) Regional Dex slot instead of orphaning in an unmatchable id.
    var taxonKey: Int?
    var scientificName: String?
    var commonName: String?
    var summary: String?
    var iucnCategory: String?

    /// The single common-name adoption rule shared by the capture and heal paths:
    /// take the enrichment's common name only when it confirms the same species
    /// (case-insensitive scientific-name match) and is non-empty; otherwise keep
    /// the caller's current name unchanged. Centralized so the two call sites can't
    /// drift (the heal copy previously omitted the non-empty guard and could blank
    /// a card title with an empty enrichment name).
    func adoptedCommonName(current commonName: String, scientificName: String) -> String {
        guard let sci = self.scientificName,
              sci.caseInsensitiveCompare(scientificName) == .orderedSame,
              let candidate = self.commonName, !candidate.isEmpty else {
            return commonName
        }
        return candidate
    }
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
                taxonKey: decoded.taxonKey,
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
        var taxonKey: Int?
        var factSheet: FactSheet
        struct FactSheet: Decodable {
            var scientificName: String?
            var commonName: String?
            var summary: String?
            var iucnCategory: String?
        }
    }
}
