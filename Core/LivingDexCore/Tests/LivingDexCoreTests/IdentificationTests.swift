import XCTest
@testable import LivingDexCore

final class IdentificationTests: XCTestCase {
    private func candidate(_ id: String, confidence: Double) -> SpeciesCandidate {
        SpeciesCandidate(
            speciesId: id, commonName: id, scientificName: id, realm: .animals, rarity: .common, confidence: confidence)
    }

    func testTopIsTheFirstCandidate() {
        let result = IdentificationResult(candidates: [candidate("a", confidence: 0.9), candidate("b", confidence: 0.4)])
        XCTAssertEqual(result.top?.speciesId, "a")
        XCTAssertNil(result.error)
    }

    func testFailureCarriesItsErrorWithoutCandidates() {
        let result = IdentificationResult(candidates: [], error: .offline)
        XCTAssertNil(result.top)
        XCTAssertEqual(result.error, .offline)
    }

    func testRealmAndRarityRoundTripThroughCodable() throws {
        let data = try JSONEncoder().encode(["realm": Realm.fungi.rawValue, "rarity": Rarity.epic.rawValue])
        let decoded = try JSONDecoder().decode([String: String].self, from: data)
        XCTAssertEqual(Realm(rawValue: decoded["realm"] ?? ""), .fungi)
        XCTAssertEqual(Rarity(rawValue: decoded["rarity"] ?? ""), .epic)
    }

    func testMinimumConfidenceGate() {
        XCTAssertEqual(IdentificationPolicy.minConfidence, 0.35)
    }

    func testCaptureContextDefaultsToNoLocation() {
        let context = CaptureContext()
        XCTAssertNil(context.latitude)
        XCTAssertNil(context.longitude)
        XCTAssertNil(context.elevationMeters)
    }
}
