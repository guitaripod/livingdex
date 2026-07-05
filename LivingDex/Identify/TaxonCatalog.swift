import Foundation

/// Maps a classifier's output label to species metadata. Backed by an optional
/// bundled `taxa.json` (`[label: TaxonInfo]`) so the on-device model's labels
/// resolve to names/realm/rarity without a network call. Empty until the
/// catalog ships alongside the model.
final class TaxonCatalog: Sendable {
    static let shared = TaxonCatalog()

    struct TaxonInfo: Codable, Sendable {
        let speciesId: String
        let commonName: String
        let scientificName: String
        let realm: Realm
        let rarity: Rarity
    }

    private let byLabel: [String: TaxonInfo]

    init(bundle: Bundle = .main) {
        if let url = bundle.url(forResource: "taxa", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let map = try? JSONDecoder().decode([String: TaxonInfo].self, from: data) {
            byLabel = map
            AppLogger.shared.info("taxon catalog loaded: \(map.count) taxa", category: .identify)
        } else {
            byLabel = [:]
        }
    }

    var isLoaded: Bool { !byLabel.isEmpty }

    func candidate(forLabel label: String, confidence: Double) -> SpeciesCandidate? {
        guard let info = byLabel[label] else { return nil }
        return SpeciesCandidate(
            speciesId: info.speciesId,
            commonName: info.commonName,
            scientificName: info.scientificName,
            realm: info.realm,
            rarity: info.rarity,
            confidence: confidence)
    }
}
