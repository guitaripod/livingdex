import AICreditsCore
import LivingDexCore
import MidgarCore
import XCTest
@testable import LivingDex

final class ModelRegionVisibilityTests: XCTestCase {

    func testEveryModelSurfaceIsOfferedWhileTheModelsWork() {
        let visibility = ModelFeatureVisibility(modelsAvailable: true)
        XCTAssertTrue(visibility.showsCloudIdentification)
        XCTAssertTrue(visibility.showsLibraryIdentification)
        XCTAssertTrue(visibility.showsCredits)
        XCTAssertTrue(visibility.presentsPaywall)
        XCTAssertTrue(visibility.showsCloudConsentSetting)
        XCTAssertNotEqual(visibility.idleStatus, MidgarModelRegion.unavailableMessage)
    }

    func testNoModelSurfaceIsOfferedWhereTheModelsDoNotWork() {
        let visibility = ModelFeatureVisibility(modelsAvailable: false)
        XCTAssertFalse(visibility.showsCloudIdentification)
        XCTAssertFalse(visibility.showsLibraryIdentification)
        XCTAssertFalse(visibility.showsCredits)
        XCTAssertFalse(visibility.presentsPaywall)
        XCTAssertFalse(visibility.showsCloudConsentSetting)
    }

    func testTheIdleLineIsTheNeutralRegionLineWhereTheModelsDoNotWork() {
        XCTAssertEqual(ModelFeatureVisibility(modelsAvailable: false).idleStatus, MidgarModelRegion.unavailableMessage)
    }

    func testTheGuideKeepsEveryEntryWhileTheModelsWork() {
        XCTAssertEqual(FieldGuide.visibleSteps(modelsAvailable: true).count, FieldGuide.steps.count)
        XCTAssertEqual(FieldGuide.visibleConcepts(modelsAvailable: true).count, FieldGuide.concepts.count)
    }

    func testTheGuideDropsTheEntriesThatDescribeTheModelsWhereTheyDoNotWork() {
        let steps = FieldGuide.visibleSteps(modelsAvailable: false)
        let concepts = FieldGuide.visibleConcepts(modelsAvailable: false)
        XCTAssertTrue(steps.allSatisfy { !$0.needsModels })
        XCTAssertTrue(concepts.allSatisfy { !$0.needsModels })
        XCTAssertEqual(steps.count, FieldGuide.steps.filter { !$0.needsModels }.count)
        XCTAssertEqual(concepts.count, FieldGuide.concepts.filter { !$0.needsModels }.count)
        XCTAssertLessThan(steps.count, FieldGuide.steps.count)
        XCTAssertLessThan(concepts.count, FieldGuide.concepts.count)
    }

    func testARegionRefusalFromMakoMapsToTheRegionError() {
        let refusal = AICreditsError.server(code: "unavailable_in_region", message: "not offered")
        XCTAssertEqual(CloudVisionIdentifier.identifyError(from: refusal), .unavailableInRegion)
    }

    func testAnOrdinaryServerFailureIsNotTheRegionError() {
        let failure = AICreditsError.server(code: nil, message: "boom")
        XCTAssertEqual(CloudVisionIdentifier.identifyError(from: failure), .serverError)
    }
}
