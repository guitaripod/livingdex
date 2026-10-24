import XCTest
@testable import LivingDexCore

final class ProgressionTests: XCTestCase {
    func testLegendaryNewIsBiggestAward() {
        XCTAssertEqual(XP.award(rarity: .legendary, isNew: true), 150)
        XCTAssertGreaterThan(XP.award(rarity: .legendary, isNew: true), XP.award(rarity: .common, isNew: true))
    }

    func testRepeatCatchesAwardATrickleRegardlessOfRarity() {
        for rarity in Rarity.allCases {
            XCTAssertEqual(XP.award(rarity: rarity, isNew: false), 3)
        }
    }

    func testLevelCurveMonotonic() {
        XCTAssertEqual(Level.level(for: 0), 1)
        XCTAssertEqual(Level.level(for: 99), 1)
        XCTAssertEqual(Level.level(for: 100), 2)
        XCTAssertGreaterThan(Level.threshold(5), Level.threshold(4))
    }

    func testProgressSpansTheCurrentLevel() {
        let progress = Level.progress(for: 130)
        XCTAssertEqual(progress.level, 2)
        XCTAssertEqual(progress.into, 30)
        XCTAssertEqual(progress.span, 150)
    }

    func testRarityOrdersFromCommonToLegendary() {
        XCTAssertEqual(Rarity.allCases.sorted(by: >), [.legendary, .epic, .rare, .uncommon, .common])
        XCTAssertTrue(Rarity.rare >= .rare)
    }
}
