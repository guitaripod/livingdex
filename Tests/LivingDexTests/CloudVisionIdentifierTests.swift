import XCTest
import AICreditsCore
@testable import LivingDex

final class CloudVisionIdentifierTests: XCTestCase {
    private func json(commonName: String = "Red Fox", scientificName: String = "Vulpes vulpes", realm: String = "animals", confidence: Double = 0.9) -> String {
        #"{"commonName":"\#(commonName)","scientificName":"\#(scientificName)","realm":"\#(realm)","confidence":\#(confidence)}"#
    }

    func testParsesCleanBinomial() {
        let candidate = CloudVisionIdentifier.parse(json())
        XCTAssertEqual(candidate?.speciesId, "sci:vulpes vulpes")
        XCTAssertEqual(candidate?.scientificName, "Vulpes vulpes")
        XCTAssertEqual(candidate?.commonName, "Red Fox")
        XCTAssertEqual(candidate?.realm, .animals)
        XCTAssertEqual(candidate?.rarity, .common)
        XCTAssertEqual(candidate?.confidence, 0.9)
    }

    func testRejectsBareGenus() {
        XCTAssertNil(CloudVisionIdentifier.parse(json(scientificName: "Vulpes")))
    }

    func testRejectsUnknownScientificName() {
        XCTAssertNil(CloudVisionIdentifier.parse(json(scientificName: "unknown")))
    }

    func testRejectsConfidenceBelowThreshold() {
        XCTAssertNil(CloudVisionIdentifier.parse(json(confidence: 0.2)))
    }

    func testClampsConfidenceAboveOne() {
        let candidate = CloudVisionIdentifier.parse(json(confidence: 1.7))
        XCTAssertEqual(candidate?.confidence, 1.0)
    }

    func testParsesFencedProseWrappedJSON() {
        let content = "Sure, here you go:\n```json\n\(json(scientificName: "Bufo bufo"))\n```"
        let candidate = CloudVisionIdentifier.parse(content)
        XCTAssertEqual(candidate?.scientificName, "Bufo bufo")
    }

    func testUnknownRealmFallsBackToOther() {
        let candidate = CloudVisionIdentifier.parse(json(realm: "minerals"))
        XCTAssertEqual(candidate?.realm, .other)
    }

    func testEmptyCommonNameFallsBackToBinomial() {
        let candidate = CloudVisionIdentifier.parse(json(commonName: ""))
        XCTAssertEqual(candidate?.commonName, "Vulpes vulpes")
    }

    func testMalformedJSONYieldsNil() {
        XCTAssertNil(CloudVisionIdentifier.parse("no organism here"))
    }

    func testInsufficientCreditsMapsToCreditsExhausted() {
        let mapped = CloudVisionIdentifier.identifyError(
            from: AICreditsError.insufficientCredits(required: 5, available: 1))
        XCTAssertEqual(mapped, .creditsExhausted)
    }

    func testTransportErrorMapsToOffline() {
        XCTAssertEqual(CloudVisionIdentifier.identifyError(from: AICreditsError.transport("down")), .offline)
    }

    func testOtherCreditsErrorMapsToServerError() {
        XCTAssertEqual(CloudVisionIdentifier.identifyError(from: AICreditsError.unauthorized), .serverError)
    }

    func testNotConnectedURLErrorMapsToOffline() {
        XCTAssertEqual(CloudVisionIdentifier.identifyError(from: URLError(.notConnectedToInternet)), .offline)
    }

    func testTimedOutURLErrorMapsToOffline() {
        XCTAssertEqual(CloudVisionIdentifier.identifyError(from: URLError(.timedOut)), .offline)
    }

    func testUnhandledURLErrorMapsToServerError() {
        XCTAssertEqual(CloudVisionIdentifier.identifyError(from: URLError(.badServerResponse)), .serverError)
    }
}
