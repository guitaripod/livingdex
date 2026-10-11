import XCTest
@testable import LivingDex

final class SpeciesEnricherTests: XCTestCase {
    func testParsesGbifKeyFromSpeciesId() {
        XCTAssertEqual(SpeciesEnricher.gbifKey(from: "gbif:5231190"), "5231190")
    }

    func testRejectsNonGbifSpeciesId() {
        XCTAssertNil(SpeciesEnricher.gbifKey(from: "col:abc"))
        XCTAssertNil(SpeciesEnricher.gbifKey(from: "5231190"))
    }

    func testCoordinatesAreRoundedToAboutElevenKilometres() {
        XCTAssertEqual(SpeciesEnricher.coarsened(60.16952), 60.2, accuracy: 0.0001)
        XCTAssertEqual(SpeciesEnricher.coarsened(24.93841), 24.9, accuracy: 0.0001)
        XCTAssertEqual(SpeciesEnricher.coarsened(-33.8688), -33.9, accuracy: 0.0001)
    }
}
