import Foundation

/// Game Center achievement identifiers (must match the ids configured in App
/// Store Connect). Percent-complete is computed from local collection state, so
/// the same evaluation drives both first-unlock and progress bars.
enum Achievement: String, CaseIterable, Sendable {
    case firstCatch = "com.guitaripod.livingdex.ach.first_catch"
    case species10 = "com.guitaripod.livingdex.ach.species_10"
    case species50 = "com.guitaripod.livingdex.ach.species_50"
    case species100 = "com.guitaripod.livingdex.ach.species_100"
    case allRealms = "com.guitaripod.livingdex.ach.all_realms"
    case firstRare = "com.guitaripod.livingdex.ach.first_rare"
    case firstLegendary = "com.guitaripod.livingdex.ach.first_legendary"
    case streak7 = "com.guitaripod.livingdex.ach.streak_7"

    /// The leaderboard for total unique species collected.
    static let speciesLeaderboardID = "com.guitaripod.livingdex.lb.species"
}

/// A snapshot of everything achievement evaluation needs, so the evaluator is a
/// pure, testable function of state.
struct AchievementContext: Sendable {
    var speciesCount: Int
    var realms: Set<Realm>
    var maxRarity: Rarity?
    var longestStreak: Int
}

extension Achievement {
    /// Percent complete (0…100) for this achievement given the context.
    func percent(_ ctx: AchievementContext) -> Double {
        func ratio(_ value: Int, _ target: Int) -> Double {
            min(100, Double(value) / Double(target) * 100)
        }
        switch self {
        case .firstCatch: return ctx.speciesCount >= 1 ? 100 : 0
        case .species10: return ratio(ctx.speciesCount, 10)
        case .species50: return ratio(ctx.speciesCount, 50)
        case .species100: return ratio(ctx.speciesCount, 100)
        case .allRealms:
            let collectable: Set<Realm> = [.animals, .plants, .fungi]
            return ratio(ctx.realms.intersection(collectable).count, collectable.count)
        case .firstRare:
            return (ctx.maxRarity.map { $0 >= .rare } ?? false) ? 100 : 0
        case .firstLegendary:
            return ctx.maxRarity == .legendary ? 100 : 0
        case .streak7: return ratio(ctx.longestStreak, 7)
        }
    }
}

extension Rarity: Comparable {
    private var order: Int { Rarity.allCases.firstIndex(of: self) ?? 0 }
    static func < (lhs: Rarity, rhs: Rarity) -> Bool { lhs.order < rhs.order }
}
