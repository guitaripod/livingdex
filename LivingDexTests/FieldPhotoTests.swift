import XCTest
@testable import LivingDex

final class FieldPhotoTests: XCTestCase {
    func testEverySampleLoadsFromTheBundle() {
        for index in SampleLibrary.names.indices {
            XCTAssertNotNil(SampleLibrary.image(at: index), SampleLibrary.names[index])
        }
    }

    func testSampleRotationWrapsAroundInBothDirections() {
        let count = SampleLibrary.names.count
        XCTAssertEqual(SampleLibrary.image(at: 0)?.size, SampleLibrary.image(at: count)?.size)
        XCTAssertNotNil(SampleLibrary.image(at: -1))
    }

    func testNextAdvancesTheCursor() {
        AppSettings.sampleCursor = 0
        _ = SampleLibrary.next()
        _ = SampleLibrary.next()
        XCTAssertEqual(AppSettings.sampleCursor, 2)
        AppSettings.sampleCursor = 0
    }

    func testDownsamplerBoundsTheLongEdge() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "sample-robin", withExtension: "jpg"))
        let image = try XCTUnwrap(ImageDownsampler.image(at: url, maxPixel: 256))
        let longEdge = max(image.size.width, image.size.height) * image.scale
        XCTAssertLessThanOrEqual(longEdge, 256)
        XCTAssertGreaterThan(longEdge, 128)
    }

    func testDownsamplerRejectsANonImage() {
        XCTAssertNil(ImageDownsampler.image(at: URL(fileURLWithPath: "/nonexistent.jpg"), maxPixel: 256))
    }
}

@MainActor
final class CloudConsentTests: XCTestCase {
    override func tearDown() {
        AppSettings.reset()
        super.tearDown()
    }

    func testProceedsImmediatelyOnceConsentWasGiven() {
        AppSettings.hasAcceptedCloudAI = true
        var ran = false
        CloudConsent.ensure(from: UIViewController()) { ran = true }
        XCTAssertTrue(ran)
    }

    func testAsksBeforeProceedingWithoutConsent() {
        AppSettings.hasAcceptedCloudAI = false
        var ran = false
        let presenter = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        CloudConsent.ensure(from: presenter) { ran = true }
        XCTAssertFalse(ran)
        XCTAssertTrue(presenter.presentedViewController is CloudConsentViewController)
    }

    func testResetReturnsEveryPreferenceToItsFirstLaunchValue() {
        AppSettings.hasOnboarded = true
        AppSettings.hasAcceptedCloudAI = true
        AppSettings.sampleCursor = 3
        AppSettings.reset()
        XCTAssertFalse(AppSettings.hasOnboarded)
        XCTAssertFalse(AppSettings.hasAcceptedCloudAI)
        XCTAssertEqual(AppSettings.sampleCursor, 0)
    }
}

final class ShareCardRendererTests: XCTestCase {
    private func model(_ rarity: Rarity, name: String = "Golden Eagle") -> ShareCardModel {
        let photo = SampleLibrary.image(at: 1) ?? UIImage()
        return ShareCardModel(
            commonName: name, scientificName: "Aquila chrysaetos", realm: .animals,
            rarity: rarity, caughtAt: Date(timeIntervalSince1970: 1_790_000_000), photo: photo)
    }

    func testRendersAFourByFiveCardForEveryRarity() {
        for rarity in Rarity.allCases {
            let image = ShareCardRenderer.render(model(rarity))
            XCTAssertEqual(image.size, ShareCardRenderer.size, rarity.rawValue)
            XCTAssertEqual(image.scale, 1)
        }
    }

    func testRarityChangesTheCard() {
        let common = ShareCardRenderer.render(model(.common)).pngData()
        let legendary = ShareCardRenderer.render(model(.legendary)).pngData()
        XCTAssertNotEqual(common, legendary)
    }

    func testAVeryLongNameStillRenders() {
        let image = ShareCardRenderer.render(model(.rare, name: String(repeating: "Extraordinarily Long Name ", count: 6)))
        XCTAssertEqual(image.size, ShareCardRenderer.size)
    }

    func testShareItemsCarryTheCardAndTheStoreLink() {
        let items = ShareCardRenderer.shareItems(for: model(.epic))
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0] is UIImage)
        XCTAssertTrue((items[1] as? String)?.contains(LegalLinks.appStore.absoluteString) ?? false)
    }
}

final class NarratorServiceTests: XCTestCase {
    private struct Stub: Narrator {
        let text: String?
        func entry(for candidate: SpeciesCandidate, grounding: String?) async -> PokedexEntry? {
            text.map { PokedexEntry(entry: $0, funFacts: [], category: nil, typicalSize: nil) }
        }
    }

    private let candidate = SpeciesCandidate(
        speciesId: "gbif:1", commonName: "Robin", scientificName: "Erithacus rubecula",
        realm: .animals, rarity: .common, confidence: 0.9)

    func testOnDeviceModelWinsWhenAvailable() async {
        let service = NarratorService(onDevice: Stub(text: "device"), cloud: Stub(text: "cloud"), isPro: { true })
        let entry = await service.entry(for: candidate, grounding: "wiki")
        XCTAssertEqual(entry?.entry, "device")
    }

    func testProMembersGetTheCloudEntryWhenThereIsNoOnDeviceModel() async {
        let service = NarratorService(onDevice: nil, cloud: Stub(text: "cloud"), isPro: { true })
        let entry = await service.entry(for: candidate, grounding: "wiki")
        XCTAssertEqual(entry?.entry, "cloud")
    }

    func testFreePlayersNeverSpendCreditsOnAnEntry() async {
        let service = NarratorService(onDevice: nil, cloud: Stub(text: "cloud"), isPro: { false })
        let entry = await service.entry(for: candidate, grounding: "A small thrush.")
        XCTAssertTrue(entry?.entry.hasPrefix("A small thrush.") ?? false)
        XCTAssertTrue(entry?.entry.contains("Wikipedia") ?? false)
    }

    func testNoSummaryAndNoModelMeansNoEntry() async {
        let service = NarratorService(onDevice: nil, cloud: Stub(text: "cloud"), isPro: { false })
        let entry = await service.entry(for: candidate, grounding: nil)
        XCTAssertNil(entry)
    }

    func testProFallsBackToTheSourcedSummaryWhenTheCloudFails() async {
        let service = NarratorService(onDevice: nil, cloud: Stub(text: nil), isPro: { true })
        let entry = await service.entry(for: candidate, grounding: "A small thrush.")
        XCTAssertTrue(entry?.entry.contains("A small thrush.") ?? false)
    }
}
