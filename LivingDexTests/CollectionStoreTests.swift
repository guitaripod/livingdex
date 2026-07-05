import XCTest
@testable import LivingDex

final class CollectionStoreTests: XCTestCase {
    private func makeStore() throws -> CollectionStore {
        let db = try DatabaseManager(inMemoryName: "test-\(UUID().uuidString)")
        return CollectionStore(dbQueue: db.dbQueue)
    }

    private func sighting(species: String = "gbif:1", rarity: Rarity = .common) -> Sighting {
        Sighting(
            id: UUID().uuidString, speciesId: species, commonName: "Test", scientificName: "Testus testus",
            realm: .animals, rarity: rarity, confidence: 0.9, capturedAt: Date(),
            latitude: nil, longitude: nil, elevationMeters: nil, imagePath: "x.jpg", pokedexEntry: nil)
    }

    func testFirstCatchIsNewEntry() throws {
        let store = try makeStore()
        XCTAssertTrue(try store.save(sighting()))
        XCTAssertEqual(try store.dexCount(), 1)
    }

    func testSecondCatchOfSameSpeciesIsNotNew() throws {
        let store = try makeStore()
        _ = try store.save(sighting(species: "gbif:42"))
        XCTAssertFalse(try store.save(sighting(species: "gbif:42")))
        XCTAssertEqual(try store.dexCount(), 1)
    }

    func testDistinctSpeciesGrowDex() throws {
        let store = try makeStore()
        _ = try store.save(sighting(species: "gbif:1"))
        _ = try store.save(sighting(species: "gbif:2"))
        XCTAssertEqual(try store.dexCount(), 2)
    }

    func testStatsCountsSpeciesCatchesAndRarity() throws {
        let store = try makeStore()
        _ = try store.save(sighting(species: "gbif:1", rarity: .common))
        _ = try store.save(sighting(species: "gbif:1", rarity: .common))
        _ = try store.save(sighting(species: "gbif:2", rarity: .rare))
        let stats = try store.stats()
        XCTAssertEqual(stats.speciesCount, 2)
        XCTAssertEqual(stats.totalCatches, 3)
        XCTAssertEqual(stats.byRarity[.common], 1)
        XCTAssertEqual(stats.byRarity[.rare], 1)
    }

    func testPokedexEntryPersists() throws {
        let store = try makeStore()
        let s = sighting(species: "gbif:7")
        _ = try store.save(s)
        let entry = PokedexEntry(entry: "A test creature.", funFacts: ["fact"], category: "Test Beast", typicalSize: "~1 cm")
        try store.setNarration(sightingId: s.id, entry: entry)
        let fetched = try store.latestSighting(speciesId: "gbif:7")
        XCTAssertEqual(fetched?.pokedexEntry, entry.displayText)
        XCTAssertEqual(fetched?.category, "Test Beast")
        XCTAssertEqual(fetched?.typicalSize, "~1 cm")
    }
}
