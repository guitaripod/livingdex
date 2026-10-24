import Foundation

/// A ranked identification candidate for a captured image.
public struct SpeciesCandidate: Sendable, Equatable {
    public var speciesId: String
    public var commonName: String
    public var scientificName: String
    public var realm: Realm
    public var rarity: Rarity
    /// 0...1 model confidence, after any geo-prior re-ranking.
    public var confidence: Double

    public init(
        speciesId: String,
        commonName: String,
        scientificName: String,
        realm: Realm,
        rarity: Rarity,
        confidence: Double
    ) {
        self.speciesId = speciesId
        self.commonName = commonName
        self.scientificName = scientificName
        self.realm = realm
        self.rarity = rarity
        self.confidence = confidence
    }
}

/// Why an identification yielded no usable candidate. Lets the capture UI show
/// distinct recovery copy per failure instead of collapsing offline, exhausted
/// credits, and server faults all into "no clear living thing".
public enum IdentifyError: Error, Sendable, Equatable {
    case offline
    case creditsExhausted
    case serverError
    case noSpecies
}

public struct IdentificationResult: Sendable {
    public var candidates: [SpeciesCandidate]
    /// Non-nil when `candidates` is empty because identification failed rather
    /// than because the frame held no confident subject; `.noSpecies` is the
    /// legitimate "nothing recognizable in frame" outcome.
    public var error: IdentifyError?
    public var top: SpeciesCandidate? { candidates.first }

    public init(candidates: [SpeciesCandidate], error: IdentifyError? = nil) {
        self.candidates = candidates
        self.error = error
    }
}

/// Location context used to re-rank candidates against a local species prior.
public struct CaptureContext: Sendable {
    public var latitude: Double?
    public var longitude: Double?
    public var elevationMeters: Double?

    public init(latitude: Double? = nil, longitude: Double? = nil, elevationMeters: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevationMeters = elevationMeters
    }
}
