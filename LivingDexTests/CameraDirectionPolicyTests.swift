import XCTest
@testable import LivingDex

final class CameraDirectionPolicyTests: XCTestCase {
    private typealias Candidate = CameraDirectionPolicy.Candidate

    private let ranking = ["triple", "dualWide", "outerUltraWide", "innerUltraWide"]

    private func candidate(_ id: String, _ type: String) -> Candidate {
        Candidate(uniqueID: id, deviceType: type)
    }

    func testKeepsTheActiveCameraWhileItStillLooksAway() {
        let backward = [candidate("a", "triple"), candidate("b", "outerUltraWide")]
        XCTAssertNil(CameraDirectionPolicy.replacement(activeID: "b", backwardFacing: backward, ranking: ranking))
    }

    func testSwitchesToTheBestRankedCameraWhenTheActiveOneTurnsToward() {
        let backward = [candidate("b", "outerUltraWide"), candidate("a", "dualWide")]
        let chosen = CameraDirectionPolicy.replacement(activeID: "gone", backwardFacing: backward, ranking: ranking)
        XCTAssertEqual(chosen?.uniqueID, "a")
    }

    func testSwitchesWhenNothingIsActiveYet() {
        let backward = [candidate("b", "innerUltraWide")]
        let chosen = CameraDirectionPolicy.replacement(activeID: nil, backwardFacing: backward, ranking: ranking)
        XCTAssertEqual(chosen?.uniqueID, "b")
    }

    func testDoesNothingWhenNoCameraLooksAway() {
        XCTAssertNil(CameraDirectionPolicy.replacement(activeID: "a", backwardFacing: [], ranking: ranking))
    }

    func testUnrankedTypesComeLastAndTiesKeepTheGivenOrder() {
        let mixed = [candidate("x", "mystery"), candidate("y", "mystery2"), candidate("z", "innerUltraWide")]
        XCTAssertEqual(CameraDirectionPolicy.replacement(activeID: nil, backwardFacing: mixed, ranking: ranking)?.uniqueID, "z")
        let unranked = [candidate("x", "mystery"), candidate("y", "mystery2")]
        XCTAssertEqual(CameraDirectionPolicy.replacement(activeID: nil, backwardFacing: unranked, ranking: ranking)?.uniqueID, "x")
    }
}
