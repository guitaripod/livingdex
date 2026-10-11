import XCTest
@testable import LivingDex

final class MakoChatTests: XCTestCase {
    func testExtractsContentFromOpenAIShapedBody() {
        let body = #"{"choices":[{"message":{"content":"hello dex"}}]}"#
        XCTAssertEqual(MakoChat.messageContent(Data(body.utf8)), "hello dex")
    }

    func testExtractsContentFromTheFlatGeminiEnvelope() {
        let body = #"{"content":"{\n  \"commonName\": \"Wood Anemone\",\n  \"confidence\": 0.95\n}","model":"gemini-2.5-flash","credits_charged":1,"usage":{"prompt_tokens":406,"output_tokens":47,"total_tokens":453}}"#
        let content = MakoChat.messageContent(Data(body.utf8))
        XCTAssertTrue(content?.contains("Wood Anemone") ?? false)
    }

    func testFlatEnvelopeWrappedInProseStillParses() {
        let body = "```json\n{\"content\":\"hi\",\"credits_charged\":1}\n```"
        XCTAssertEqual(MakoChat.messageContent(Data(body.utf8)), "hi")
    }

    func testExtractsBalancedObjectFromFencedProse() {
        let content = "Sure!\n```json\n{\"entry\":\"A bird.\",\"funFacts\":[\"flies\"]}\n```"
        let json = MakoChat.firstBalancedObject(in: content)
        XCTAssertNotNil(json)
        let decoded = try? JSONDecoder().decode(PokedexEntry.self, from: Data(json!.utf8))
        XCTAssertEqual(decoded?.entry, "A bird.")
        XCTAssertEqual(decoded?.funFacts, ["flies"])
    }

    func testPokedexEntryDisplayText() {
        let entry = PokedexEntry(entry: "The house sparrow.", funFacts: ["Loud", "Social"])
        XCTAssertEqual(entry.displayText, "The house sparrow.\n\n• Loud\n\n• Social")
    }

    func testMalformedBodyYieldsNil() {
        XCTAssertNil(MakoChat.messageContent(Data("not json".utf8)))
    }
}
