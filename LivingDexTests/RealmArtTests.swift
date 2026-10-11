import XCTest
@testable import LivingDex

@MainActor
final class RealmArtTests: XCTestCase {
    func testEveryRealmHasAnIllustration() {
        for realm in Realm.allCases {
            XCTAssertNotNil(RealmArt.image(for: realm), "missing art for \(realm.rawValue)")
        }
    }

    func testTileIsTheSameForTheSameSlot() {
        let first = RealmArt.tile(for: .animals, seed: 4)
        let again = RealmArt.tile(for: .animals, seed: 4)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === again)
    }

    func testSixteenSlotsCycleThroughDistinctCrops() {
        let tiles = (0..<16).compactMap { RealmArt.tile(for: .plants, seed: $0) }
        XCTAssertEqual(tiles.count, 16)
        XCTAssertEqual(Set(tiles.map { ObjectIdentifier($0) }).count, 16)
        XCTAssertTrue(RealmArt.tile(for: .plants, seed: 16) === tiles[0])
    }

    func testSeedIsStableAndSpreadsSpecies() {
        XCTAssertEqual(RealmArt.seed(for: "gbif:2480242"), RealmArt.seed(for: "gbif:2480242"))
        let seeds = Set((0..<40).map { RealmArt.seed(for: "gbif:\($0)") % 16 })
        XCTAssertGreaterThan(seeds.count, 8)
    }

    func testNegativeSeedsAreSafe() {
        XCTAssertNotNil(RealmArt.tile(for: .fungi, seed: -7))
    }

    func testTilesAreSquareCropsOfTheArt() throws {
        let tile = try XCTUnwrap(RealmArt.tile(for: .protists, seed: 2)?.cgImage)
        XCTAssertEqual(tile.width, tile.height)
        let source = try XCTUnwrap(RealmArt.image(for: .protists)?.cgImage)
        XCTAssertLessThan(tile.width, source.width)
    }
}
