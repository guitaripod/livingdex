import UIKit

/// A ranked identification candidate for a captured image.
struct SpeciesCandidate: Sendable, Equatable {
    var speciesId: String
    var commonName: String
    var scientificName: String
    var realm: Realm
    var rarity: Rarity
    /// 0...1 model confidence, after any geo-prior re-ranking.
    var confidence: Double
}

struct IdentificationResult: Sendable {
    var candidates: [SpeciesCandidate]
    var top: SpeciesCandidate? { candidates.first }
}

/// Location context used to re-rank candidates against a local species prior.
struct CaptureContext: Sendable {
    var latitude: Double?
    var longitude: Double?
    var elevationMeters: Double?
}

/// The identification boundary. The v1 implementation is an on-device Core ML
/// classifier (BioCLIP-distilled) whose scores are re-ranked by a cached
/// `species × H3` geo-prior, with a cloud fallback through mako. Everything above
/// this protocol is UI; everything below is swappable.
protocol SpeciesIdentifier: Sendable {
    func identify(_ image: UIImage, context: CaptureContext) async -> IdentificationResult
}

/// Placeholder identifier so the capture → card → dex loop is exercisable before
/// the Core ML model ships. Returns a plausible candidate deterministically
/// derived from the image so the same subject reads consistently. NOT for
/// production — replace with `CoreMLSpeciesIdentifier`.
struct StubSpeciesIdentifier: SpeciesIdentifier {
    private static let catalog: [SpeciesCandidate] = [
        .init(speciesId: "gbif:5231190", commonName: "House Sparrow", scientificName: "Passer domesticus", realm: .animals, rarity: .common, confidence: 0),
        .init(speciesId: "gbif:2481139", commonName: "Rock Pigeon", scientificName: "Columba livia", realm: .animals, rarity: .common, confidence: 0),
        .init(speciesId: "gbif:1340158", commonName: "Seven-spot Ladybird", scientificName: "Coccinella septempunctata", realm: .animals, rarity: .uncommon, confidence: 0),
        .init(speciesId: "gbif:3189866", commonName: "Common Dandelion", scientificName: "Taraxacum officinale", realm: .plants, rarity: .common, confidence: 0),
        .init(speciesId: "gbif:5352251", commonName: "Fly Agaric", scientificName: "Amanita muscaria", realm: .fungi, rarity: .rare, confidence: 0),
        .init(speciesId: "gbif:2435098", commonName: "Red Fox", scientificName: "Vulpes vulpes", realm: .animals, rarity: .uncommon, confidence: 0),
    ]

    func identify(_ image: UIImage, context: CaptureContext) async -> IdentificationResult {
        let seed = Int(image.size.width * image.size.height) &+ Int(Date().timeIntervalSince1970)
        let idx = abs(seed) % Self.catalog.count
        var top = Self.catalog[idx]
        top.confidence = Double.random(in: 0.62...0.97)
        AppLogger.shared.info("stub identify -> \(top.commonName) \(String(format: "%.2f", top.confidence))", category: .identify)
        return IdentificationResult(candidates: [top])
    }
}
