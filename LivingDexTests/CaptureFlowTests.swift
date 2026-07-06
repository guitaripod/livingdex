import XCTest
import UIKit
@testable import LivingDex

final class CaptureFlowTests: XCTestCase {
    private struct SaveFailure: Error {}

    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    private func candidate(confidence: Double = 0.9) -> SpeciesCandidate {
        SpeciesCandidate(
            speciesId: "sci:vulpes vulpes", commonName: "Fox", scientificName: "Vulpes vulpes",
            realm: .animals, rarity: .common, confidence: confidence)
    }

    private func enrichment() -> SpeciesEnrichment {
        SpeciesEnrichment(
            rarity: .rare, taxonKey: 5219243, scientificName: "Vulpes vulpes",
            commonName: "Red Fox", summary: "A fox.", iucnCategory: "LC")
    }

    private func makeFlow(
        identify: IdentificationResult,
        enrich: EnrichmentResult,
        imageStore: MockImageStore = MockImageStore(),
        sightingStore: MockSightingStore = MockSightingStore(),
        progress: MockProgress = MockProgress(),
        reporter: MockReporter = MockReporter()
    ) -> CaptureFlow {
        CaptureFlow(
            identifier: MockIdentifier(identify),
            enricher: MockEnricher(enrich),
            imageStore: imageStore,
            sightingStore: sightingStore,
            progress: progress,
            reporter: reporter,
            clock: { Date(timeIntervalSince1970: 1_000) })
    }

    func testSuccessMintsUnifiesIdToGbifAndAwards() async throws {
        let sightingStore = MockSightingStore(isNew: true)
        let progress = MockProgress()
        let reporter = MockReporter()
        let imageStore = MockImageStore()
        let flow = makeFlow(
            identify: IdentificationResult(candidates: [candidate()]),
            enrich: .resolved(enrichment()),
            imageStore: imageStore, sightingStore: sightingStore, progress: progress, reporter: reporter)

        let outcome = await flow.run(image: image(), context: CaptureContext(latitude: 60, longitude: 25, elevationMeters: nil))

        guard case let .minted(minted) = outcome else { return XCTFail("expected minted, got \(outcome)") }
        XCTAssertEqual(minted.sighting.speciesId, "gbif:5219243")
        XCTAssertEqual(minted.sighting.scientificName, "Vulpes vulpes")
        XCTAssertEqual(minted.sighting.commonName, "Red Fox")
        XCTAssertEqual(minted.sighting.rarity, .rare)
        XCTAssertTrue(minted.sighting.enriched)
        XCTAssertFalse(minted.provisional)
        XCTAssertTrue(minted.isNew)
        XCTAssertEqual(minted.sighting.capturedAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(sightingStore.saved.value.count, 1)
        XCTAssertEqual(progress.recordCount.value, 1)
        XCTAssertEqual(reporter.reportCount.value, 1)
    }

    func testSaveFailureAbortsRewardsAndDeletesOrphanImage() async throws {
        let sightingStore = MockSightingStore(error: SaveFailure())
        let progress = MockProgress()
        let reporter = MockReporter()
        let imageStore = MockImageStore(savePath: "images/orphan.jpg")
        let flow = makeFlow(
            identify: IdentificationResult(candidates: [candidate()]),
            enrich: .resolved(enrichment()),
            imageStore: imageStore, sightingStore: sightingStore, progress: progress, reporter: reporter)

        let outcome = await flow.run(image: image(), context: CaptureContext(latitude: nil, longitude: nil, elevationMeters: nil))

        guard case .saveFailed = outcome else { return XCTFail("expected saveFailed, got \(outcome)") }
        XCTAssertEqual(imageStore.deleted.value, ["images/orphan.jpg"])
        XCTAssertEqual(progress.recordCount.value, 0)
        XCTAssertEqual(reporter.reportCount.value, 0)
    }

    func testImageSaveFailureIsSaveFailedWithoutAwards() async {
        let progress = MockProgress()
        let flow = makeFlow(
            identify: IdentificationResult(candidates: [candidate()]),
            enrich: .resolved(enrichment()),
            imageStore: MockImageStore(savePath: nil), progress: progress)

        let outcome = await flow.run(image: image(), context: CaptureContext(latitude: nil, longitude: nil, elevationMeters: nil))
        guard case .saveFailed = outcome else { return XCTFail("expected saveFailed, got \(outcome)") }
        XCTAssertEqual(progress.recordCount.value, 0)
    }

    func testUnavailableEnrichmentMintsProvisionalKeepingSciId() async {
        let flow = makeFlow(
            identify: IdentificationResult(candidates: [candidate()]),
            enrich: .unavailable)

        let outcome = await flow.run(image: image(), context: CaptureContext(latitude: nil, longitude: nil, elevationMeters: nil))
        guard case let .minted(minted) = outcome else { return XCTFail("expected minted, got \(outcome)") }
        XCTAssertTrue(minted.provisional)
        XCTAssertFalse(minted.sighting.enriched)
        XCTAssertEqual(minted.sighting.speciesId, "sci:vulpes vulpes")
        XCTAssertEqual(minted.sighting.rarity, .common)
    }

    func testUnresolvedEnrichmentIsRejectedNeverMinted() async {
        let sightingStore = MockSightingStore()
        let progress = MockProgress()
        let flow = makeFlow(
            identify: IdentificationResult(candidates: [candidate()]),
            enrich: .unresolved,
            sightingStore: sightingStore, progress: progress)

        let outcome = await flow.run(image: image(), context: CaptureContext(latitude: nil, longitude: nil, elevationMeters: nil))
        guard case .unresolvedSpecies = outcome else { return XCTFail("expected unresolvedSpecies, got \(outcome)") }
        XCTAssertTrue(sightingStore.saved.value.isEmpty)
        XCTAssertEqual(progress.recordCount.value, 0)
    }

    func testLowConfidenceCandidateIsNotMinted() async {
        let flow = makeFlow(
            identify: IdentificationResult(candidates: [candidate(confidence: 0.2)]),
            enrich: .resolved(enrichment()))
        let outcome = await flow.run(image: image(), context: CaptureContext(latitude: nil, longitude: nil, elevationMeters: nil))
        guard case .lowConfidence = outcome else { return XCTFail("expected lowConfidence, got \(outcome)") }
    }

    func testIdentifyFailurePropagatesTypedError() async {
        let flow = makeFlow(
            identify: IdentificationResult(candidates: [], error: .creditsExhausted),
            enrich: .resolved(enrichment()))
        let outcome = await flow.run(image: image(), context: CaptureContext(latitude: nil, longitude: nil, elevationMeters: nil))
        guard case let .identifyFailed(error) = outcome else { return XCTFail("expected identifyFailed, got \(outcome)") }
        XCTAssertEqual(error, .creditsExhausted)
    }
}

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
    func mutate(_ body: (inout T) -> Void) {
        lock.lock(); defer { lock.unlock() }
        body(&stored)
    }
}

private final class MockIdentifier: SpeciesIdentifier, @unchecked Sendable {
    private let result: IdentificationResult
    init(_ result: IdentificationResult) { self.result = result }
    func identify(_ image: UIImage, context: CaptureContext) async -> IdentificationResult { result }
}

private final class MockEnricher: SpeciesEnriching, @unchecked Sendable {
    private let result: EnrichmentResult
    init(_ result: EnrichmentResult) { self.result = result }
    func enrich(candidate: SpeciesCandidate, context: CaptureContext) async -> EnrichmentResult { result }
}

private final class MockImageStore: CaptureImageStoring, @unchecked Sendable {
    private let savePath: String?
    let deleted = Box<[String]>([])
    init(savePath: String? = "images/x.jpg") { self.savePath = savePath }
    func save(_ image: UIImage, id: String) -> String? { savePath }
    func delete(_ relativePath: String) { deleted.mutate { $0.append(relativePath) } }
}

private final class MockSightingStore: SightingPersisting, @unchecked Sendable {
    private let isNew: Bool
    private let error: Error?
    let saved = Box<[Sighting]>([])
    init(isNew: Bool = true, error: Error? = nil) {
        self.isNew = isNew
        self.error = error
    }
    func save(_ sighting: Sighting) throws -> Bool {
        if let error { throw error }
        saved.mutate { $0.append(sighting) }
        return isNew
    }
    func stats() throws -> CollectionStore.Stats {
        CollectionStore.Stats(speciesCount: 1, totalCatches: 1, byRarity: [:], realms: [.animals], maxRarity: .rare)
    }
}

private final class MockProgress: ProgressRecording, @unchecked Sendable {
    let recordCount = Box(0)
    func record(rarity: Rarity, isNew: Bool, now: Date) throws -> ProgressEvent {
        recordCount.mutate { $0 += 1 }
        return ProgressEvent(xpGained: 10, totalXP: 10, leveledUpTo: nil, streak: 1, streakExtended: true, usedFreeze: false)
    }
    func current() throws -> PlayerProgress { .initial() }
}

private final class MockReporter: CatchReporting, @unchecked Sendable {
    let reportCount = Box(0)
    func report(_ context: AchievementContext) async { reportCount.mutate { $0 += 1 } }
}
