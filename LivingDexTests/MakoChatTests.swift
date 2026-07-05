import XCTest
@testable import LivingDex

final class MakoChatTests: XCTestCase {
    func testExtractsContentFromOpenAIShapedBody() {
        let body = #"{"choices":[{"message":{"content":"hello dex"}}]}"#
        XCTAssertEqual(MakoChat.messageContent(Data(body.utf8)), "hello dex")
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
