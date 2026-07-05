import XCTest
@testable import LivingDex

final class ProgressStoreTests: XCTestCase {
    private func makeStore() throws -> ProgressStore {
        let db = try DatabaseManager(inMemoryName: "prog-\(UUID().uuidString)")
        return ProgressStore(dbQueue: db.dbQueue)
    }

    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: Double(n) * 86_400 + 3600) }

    func testXPAwardsAndAccumulates() throws {
        let store = try makeStore()
        let e1 = try store.record(rarity: .rare, isNew: true, now: day(0))
        XCTAssertEqual(e1.xpGained, 40)
        XCTAssertEqual(e1.totalXP, 40)
        let e2 = try store.record(rarity: .common, isNew: false, now: day(0))
        XCTAssertEqual(e2.xpGained, 3)
        XCTAssertEqual(e2.totalXP, 43)
    }

    func testLegendaryNewIsBiggestAward() throws {
        XCTAssertEqual(XP.award(rarity: .legendary, isNew: true), 150)
        XCTAssertGreaterThan(XP.award(rarity: .legendary, isNew: true), XP.award(rarity: .common, isNew: true))
    }

    func testLevelCurveMonotonic() {
        XCTAssertEqual(Level.level(for: 0), 1)
        XCTAssertEqual(Level.level(for: 99), 1)
        XCTAssertEqual(Level.level(for: 100), 2)
        XCTAssertGreaterThan(Level.threshold(5), Level.threshold(4))
    }

    func testStreakExtendsOnConsecutiveDays() throws {
        let store = try makeStore()
        _ = try store.record(rarity: .common, isNew: true, now: day(10))
        let e = try store.record(rarity: .common, isNew: true, now: day(11))
        XCTAssertEqual(e.streak, 2)
        XCTAssertTrue(e.streakExtended)
    }

    func testSameDayDoesNotDoubleCountStreak() throws {
        let store = try makeStore()
        _ = try store.record(rarity: .common, isNew: true, now: day(10))
        let e = try store.record(rarity: .common, isNew: false, now: day(10))
        XCTAssertEqual(e.streak, 1)
        XCTAssertFalse(e.streakExtended)
    }

    func testFreezeAbsorbsOneMissedDay() throws {
        let store = try makeStore()
        _ = try store.record(rarity: .common, isNew: true, now: day(10)) // streak 1, 2 freezes
        let e = try store.record(rarity: .common, isNew: true, now: day(12)) // missed day 11
        XCTAssertTrue(e.usedFreeze)
        XCTAssertEqual(e.streak, 2)
        XCTAssertEqual(try store.current().freezes, PlayerProgress.initialFreezes - 1)
    }

    func testLargeGapResetsStreak() throws {
        let store = try makeStore()
        _ = try store.record(rarity: .common, isNew: true, now: day(10))
        let e = try store.record(rarity: .common, isNew: true, now: day(20))
        XCTAssertEqual(e.streak, 1)
        XCTAssertFalse(e.streakExtended)
    }

    func testLevelUpReported() throws {
        let store = try makeStore()
        var last: ProgressEvent!
        for i in 0..<12 { last = try store.record(rarity: .legendary, isNew: true, now: day(i)) }
        XCTAssertGreaterThan(last.totalXP, 100)
        XCTAssertGreaterThanOrEqual(try store.current().level, 2)
    }
}
