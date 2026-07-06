import XCTest
import UIKit
@testable import LivingDex

final class CollectionStoreTests: XCTestCase {
    private func makeStore() throws -> CollectionStore {
        let db = try DatabaseManager(inMemoryName: "test-\(UUID().uuidString)")
        return CollectionStore(dbQueue: db.dbQueue)
    }

    private func sighting(species: String = "gbif:1", rarity: Rarity = .common, enriched: Bool = false) -> Sighting {
        Sighting(
            id: UUID().uuidString, speciesId: species, commonName: "Test", scientificName: "Testus testus",
            realm: .animals, rarity: rarity, confidence: 0.9, capturedAt: Date(),
            latitude: nil, longitude: nil, elevationMeters: nil, imagePath: "x.jpg", pokedexEntry: nil,
            enriched: enriched)
    }

    private func solidImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
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

    func testHealAppliesRarityNamesAndMarksEntryAndSightingsEnriched() throws {
        let store = try makeStore()
        _ = try store.save(sighting(species: "gbif:5", rarity: .common))
        _ = try store.save(sighting(species: "gbif:5", rarity: .common))

        let healed = try store.healEnrichment(
            speciesId: "gbif:5", rarity: .legendary, commonName: "Red Fox", scientificName: "Vulpes vulpes")
        XCTAssertEqual(healed?.rarity, .legendary)
        XCTAssertEqual(healed?.commonName, "Red Fox")
        XCTAssertEqual(healed?.scientificName, "Vulpes vulpes")
        XCTAssertEqual(healed?.enriched, true)

        let latest = try store.latestSighting(speciesId: "gbif:5")
        XCTAssertEqual(latest?.rarity, .legendary)
        XCTAssertEqual(latest?.commonName, "Red Fox")
        XCTAssertEqual(latest?.scientificName, "Vulpes vulpes")
        XCTAssertEqual(latest?.enriched, true)
    }

    func testHealIsIdempotentOnceEnriched() throws {
        let store = try makeStore()
        _ = try store.save(sighting(species: "gbif:5"))
        _ = try store.healEnrichment(speciesId: "gbif:5", rarity: .rare, commonName: "First", scientificName: "Aaa aaa")

        let second = try store.healEnrichment(
            speciesId: "gbif:5", rarity: .legendary, commonName: "Second", scientificName: "Bbb bbb")
        XCTAssertEqual(second?.rarity, .rare)
        XCTAssertEqual(second?.commonName, "First")
        XCTAssertEqual(second?.scientificName, "Aaa aaa")
        XCTAssertEqual(second?.enriched, true)
    }

    func testHealReturnsNilForUnknownSpecies() throws {
        let store = try makeStore()
        XCTAssertNil(try store.healEnrichment(
            speciesId: "gbif:404", rarity: .rare, commonName: "X", scientificName: "Y y"))
    }

    func testHealDoesNotTouchAlreadyEnrichedCapture() throws {
        let store = try makeStore()
        _ = try store.save(sighting(species: "gbif:9", rarity: .epic, enriched: true))
        let healed = try store.healEnrichment(
            speciesId: "gbif:9", rarity: .common, commonName: "Downgrade", scientificName: "No no")
        XCTAssertEqual(healed?.rarity, .epic)
        XCTAssertEqual(healed?.commonName, "Test")
    }

    func testReleaseRemovesAllSightingsDexEntryAndPhotosLeavingOthers() throws {
        let store = try makeStore()
        let path = ImageStore.save(solidImage(), id: "release-\(UUID().uuidString)")
        let storedPath = try XCTUnwrap(path)
        var doomed = sighting(species: "gbif:99")
        doomed.imagePath = storedPath
        _ = try store.save(doomed)
        _ = try store.save(sighting(species: "gbif:99"))
        _ = try store.save(sighting(species: "gbif:1"))
        XCTAssertNotNil(ImageStore.load(storedPath))
        XCTAssertEqual(try store.dexCount(), 2)

        try store.release(speciesId: "gbif:99")

        XCTAssertNil(try store.latestSighting(speciesId: "gbif:99"))
        XCTAssertNil(ImageStore.load(storedPath))
        XCTAssertEqual(try store.dexCount(), 1)
        XCTAssertNotNil(try store.latestSighting(speciesId: "gbif:1"))
    }
}
