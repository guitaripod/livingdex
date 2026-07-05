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
}
