import XCTest
@testable import LivingDex

final class StarterCatalogTests: XCTestCase {
    func testEveryStarterIsAUniqueRealSpeciesWithBundledArt() {
        let starters = StarterCatalog.all
        XCTAssertEqual(starters.count, 4)
        XCTAssertEqual(Set(starters.map(\.id)).count, starters.count)
        XCTAssertEqual(Set(starters.map(\.speciesId)).count, starters.count)
        for starter in starters {
            XCTAssertTrue(starter.speciesId.hasPrefix("gbif:"), starter.id)
            XCTAssertNotNil(starter.image, starter.id)
            XCTAssertFalse(starter.entry.isEmpty, starter.id)
            XCTAssertEqual(starter.scientificName.split(separator: " ").count, 2, starter.id)
            XCTAssertEqual(starter.candidate.speciesId, starter.speciesId)
        }
    }

    func testTheChoicesSpanTheCollectableRealms() {
        XCTAssertEqual(Set(StarterCatalog.all.map(\.realm)), [.animals, .plants, .fungi])
    }
}

final class StarterCatchTests: XCTestCase {
    /// Every read and write of its mutable state happens under its lock, so sharing it between tasks is safe.
    private final class Images: CaptureImageStoring, @unchecked Sendable {
        private let lock = NSLock()
        private var removed: [String] = []
        let path: String?
        init(path: String? = "images/starter.jpg") { self.path = path }
        func save(_ image: UIImage, id: String) -> String? { path }
        func delete(_ relativePath: String) {
            lock.lock(); defer { lock.unlock() }
            removed.append(relativePath)
        }
        var deleted: [String] {
            lock.lock(); defer { lock.unlock() }
            return removed
        }
    }

    /// Every read and write of its mutable state happens under its lock, so sharing it between tasks is safe.
    private final class Sightings: SightingPersisting, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Sighting] = []
        let fails: Bool
        init(fails: Bool = false) { self.fails = fails }
        func save(_ sighting: Sighting) throws -> Bool {
            if fails { throw NSError(domain: "test", code: 1) }
            lock.lock(); defer { lock.unlock() }
            stored.append(sighting)
            return true
        }
        func stats() throws -> CollectionStore.Stats {
            CollectionStore.Stats(speciesCount: 0, totalCatches: 0, byRarity: [:], realms: [], maxRarity: nil)
        }
        var saved: [Sighting] {
            lock.lock(); defer { lock.unlock() }
            return stored
        }
    }

    /// Every read and write of its mutable state happens under its lock, so sharing it between tasks is safe.
    private final class Progress: ProgressRecording, @unchecked Sendable {
        private let lock = NSLock()
        private var rarities: [Rarity] = []
        func record(rarity: Rarity, isNew: Bool, now: Date) throws -> ProgressEvent {
            lock.lock(); defer { lock.unlock() }
            rarities.append(rarity)
            return ProgressEvent(xpGained: 10, totalXP: 10, leveledUpTo: nil, streak: 1, streakExtended: true, usedFreeze: false)
        }
        func current() throws -> PlayerProgress { .initial() }
        var recorded: [Rarity] {
            lock.lock(); defer { lock.unlock() }
            return rarities
        }
    }

    private let robin = StarterCatalog.all[0]
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeCatch(images: Images = Images(), sightings: Sightings = Sightings(), progress: Progress = Progress()) -> StarterCatch {
        StarterCatch(imageStore: images, sightingStore: sightings, progress: progress, clock: { Date(timeIntervalSince1970: 1_790_000_000) })
    }

    func testMintsTheStarterAsAFirstCatchWithItsCuratedEntry() throws {
        let sightings = Sightings()
        let progress = Progress()
        let outcome = try XCTUnwrap(makeCatch(sightings: sightings, progress: progress).mint(robin, enrichment: nil))
        let saved = try XCTUnwrap(sightings.saved.first)
        XCTAssertEqual(saved.speciesId, "gbif:2492462")
        XCTAssertEqual(saved.commonName, "European Robin")
        XCTAssertEqual(saved.pokedexEntry, robin.entry)
        XCTAssertEqual(saved.category, robin.category)
        XCTAssertEqual(saved.imagePath, "images/starter.jpg")
        XCTAssertEqual(saved.capturedAt, now)
        XCTAssertNil(saved.latitude)
        XCTAssertEqual(saved.rarity, .common)
        XCTAssertFalse(saved.enriched)
        XCTAssertTrue(outcome.isNew)
        XCTAssertEqual(outcome.progress?.xpGained, 10)
        XCTAssertEqual(progress.recorded, [.common])
    }

    func testAdoptsTheRarityAndNameTheWorkerConfirmed() throws {
        let enrichment = SpeciesEnrichment(
            rarity: .rare, taxonKey: 2492462, scientificName: "Erithacus rubecula",
            commonName: "Robin Redbreast", summary: nil, iucnCategory: nil)
        let sightings = Sightings()
        let progress = Progress()
        _ = makeCatch(sightings: sightings, progress: progress).mint(robin, enrichment: enrichment)
        let saved = try XCTUnwrap(sightings.saved.first)
        XCTAssertEqual(saved.rarity, .rare)
        XCTAssertEqual(saved.commonName, "Robin Redbreast")
        XCTAssertTrue(saved.enriched)
        XCTAssertEqual(progress.recorded, [.rare])
    }

    func testAFailedWriteLeavesNothingBehind() {
        let images = Images()
        let progress = Progress()
        let outcome = makeCatch(images: images, sightings: Sightings(fails: true), progress: progress).mint(robin, enrichment: nil)
        XCTAssertNil(outcome)
        XCTAssertEqual(images.deleted, ["images/starter.jpg"])
        XCTAssertTrue(progress.recorded.isEmpty)
    }

    func testAnUnsavableImageMintsNothing() {
        let sightings = Sightings()
        let outcome = makeCatch(images: Images(path: nil), sightings: sightings).mint(robin, enrichment: nil)
        XCTAssertNil(outcome)
        XCTAssertTrue(sightings.saved.isEmpty)
    }
}

final class OnboardingSettingsTests: XCTestCase {
    func testResetForgetsTheStarterAndTheHint() {
        AppSettings.hasChosenStarter = true
        AppSettings.hasSeenFieldHint = true
        AppSettings.reset()
        XCTAssertFalse(AppSettings.hasChosenStarter)
        XCTAssertFalse(AppSettings.hasSeenFieldHint)
    }
}
