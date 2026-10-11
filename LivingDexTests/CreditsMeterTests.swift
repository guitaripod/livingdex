import Combine
import XCTest
@testable import LivingDex

@MainActor
final class CreditsMeterTests: XCTestCase {
    private struct StubStore: AICreditsStoreProviding {
        let subject: CurrentValueSubject<Int, Never>
        var balances: AnyPublisher<Int, Never> { subject.eraseToAnyPublisher() }
    }

    func testStaysUnknownUntilTheBackendAnswers() {
        let subject = CurrentValueSubject<Int, Never>(0)
        let meter = CreditsMeter()
        meter.start(store: StubStore(subject: subject))
        XCTAssertNil(meter.knownBalance)
    }

    func testAnAnswerOfZeroIsKnown() {
        let subject = CurrentValueSubject<Int, Never>(0)
        let meter = CreditsMeter()
        meter.start(store: StubStore(subject: subject))
        subject.send(0)
        XCTAssertEqual(meter.knownBalance, 0)
    }

    func testFollowsLaterBalanceChanges() {
        let subject = CurrentValueSubject<Int, Never>(0)
        let meter = CreditsMeter()
        meter.start(store: StubStore(subject: subject))
        subject.send(27)
        subject.send(26)
        XCTAssertEqual(meter.knownBalance, 26)
    }

    func testResetReturnsToUnknown() {
        let subject = CurrentValueSubject<Int, Never>(0)
        let meter = CreditsMeter()
        meter.start(store: StubStore(subject: subject))
        subject.send(5)
        meter.reset()
        XCTAssertNil(meter.knownBalance)
    }

    func testStartingTwiceDoesNotDoubleSubscribe() {
        let subject = CurrentValueSubject<Int, Never>(0)
        let meter = CreditsMeter()
        meter.start(store: StubStore(subject: subject))
        meter.start(store: StubStore(subject: subject))
        subject.send(9)
        XCTAssertEqual(meter.knownBalance, 9)
    }
}
