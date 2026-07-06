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

/// Why an identification yielded no usable candidate. Lets the capture UI show
/// distinct recovery copy per failure instead of collapsing offline, exhausted
/// credits, and server faults all into "no clear living thing".
enum IdentifyError: Error, Sendable, Equatable {
    case offline
    case creditsExhausted
    case serverError
    case noSpecies
}

struct IdentificationResult: Sendable {
    var candidates: [SpeciesCandidate]
    /// Non-nil when `candidates` is empty because identification failed rather
    /// than because the frame held no confident subject; `.noSpecies` is the
    /// legitimate "nothing recognizable in frame" outcome.
    var error: IdentifyError?
    var top: SpeciesCandidate? { candidates.first }

    init(candidates: [SpeciesCandidate], error: IdentifyError? = nil) {
        self.candidates = candidates
        self.error = error
    }
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
