import XCTest
@testable import LivingDex

final class AchievementTests: XCTestCase {
    private func ctx(species: Int = 0, realms: Set<Realm> = [], maxRarity: Rarity? = nil, streak: Int = 0) -> AchievementContext {
        AchievementContext(speciesCount: species, realms: realms, maxRarity: maxRarity, longestStreak: streak)
    }

    func testFirstCatchUnlocksAtOne() {
        XCTAssertEqual(Achievement.firstCatch.percent(ctx(species: 0)), 0)
        XCTAssertEqual(Achievement.firstCatch.percent(ctx(species: 1)), 100)
    }

    func testSpeciesMilestonesAreProportional() {
        XCTAssertEqual(Achievement.species10.percent(ctx(species: 5)), 50)
        XCTAssertEqual(Achievement.species10.percent(ctx(species: 10)), 100)
        XCTAssertEqual(Achievement.species50.percent(ctx(species: 100)), 100) // capped
    }

    func testAllRealmsNeedsThree() {
        XCTAssertEqual(Achievement.allRealms.percent(ctx(realms: [.animals])), 100.0 / 3, accuracy: 0.01)
        XCTAssertEqual(Achievement.allRealms.percent(ctx(realms: [.animals, .plants, .fungi])), 100)
        // Non-collectable realms don't inflate progress.
        XCTAssertEqual(Achievement.allRealms.percent(ctx(realms: [.animals, .protists])), 100.0 / 3, accuracy: 0.01)
    }

    func testRarityAchievements() {
        XCTAssertEqual(Achievement.firstRare.percent(ctx(maxRarity: .uncommon)), 0)
        XCTAssertEqual(Achievement.firstRare.percent(ctx(maxRarity: .rare)), 100)
        XCTAssertEqual(Achievement.firstRare.percent(ctx(maxRarity: .legendary)), 100)
        XCTAssertEqual(Achievement.firstLegendary.percent(ctx(maxRarity: .epic)), 0)
        XCTAssertEqual(Achievement.firstLegendary.percent(ctx(maxRarity: .legendary)), 100)
    }

    func testRarityIsComparable() {
        XCTAssertTrue(Rarity.common < Rarity.legendary)
        XCTAssertTrue(Rarity.rare < Rarity.epic)
    }

    func testStreakAchievement() {
        XCTAssertEqual(Achievement.streak7.percent(ctx(streak: 7)), 100)
        XCTAssertLessThan(Achievement.streak7.percent(ctx(streak: 3)), 100)
    }
}
