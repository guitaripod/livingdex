import Foundation
import GRDB

/// XP awarded for a catch. New species are the big beats (rarity-weighted);
/// repeats give a small trickle so revisiting is still rewarded.
enum XP {
    static func award(rarity: Rarity, isNew: Bool) -> Int {
        guard isNew else { return 3 }
        switch rarity {
        case .common: return 10
        case .uncommon: return 20
        case .rare: return 40
        case .epic: return 80
        case .legendary: return 150
        }
    }
}

/// Level curve: each level costs progressively more XP. Pure and deterministic
/// so progression is testable and predictable.
enum Level {
    /// Total XP required to *reach* the start of a given level (level 1 == 0).
    static func threshold(_ level: Int) -> Int {
        guard level > 1 else { return 0 }
        // 100, +150, +200, … cumulative — a gentle quadratic ramp.
        var total = 0
        for l in 1..<level { total += 100 + (l - 1) * 50 }
        return total
    }

    /// The level for a given total XP (1-indexed).
    static func level(for xp: Int) -> Int {
        var level = 1
        while xp >= threshold(level + 1) { level += 1 }
        return level
    }

    /// Progress within the current level: (level, xpIntoLevel, xpForThisLevel).
    static func progress(for xp: Int) -> (level: Int, into: Int, span: Int) {
        let level = level(for: xp)
        let base = threshold(level)
        let next = threshold(level + 1)
        return (level, xp - base, max(1, next - base))
    }
}

/// Persistent, singleton player progression (one row). `dayNumber` is a stable
/// day index (local calendar) used for streak continuity.
struct PlayerProgress: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "player_progress"

    var id: Int64
    var totalXP: Int
    var currentStreak: Int
    var longestStreak: Int
    var lastCatchDay: Int?
    var freezes: Int

    static let singletonID: Int64 = 1
    static let initialFreezes = 2

    static func initial() -> PlayerProgress {
        PlayerProgress(id: singletonID, totalXP: 0, currentStreak: 0, longestStreak: 0, lastCatchDay: nil, freezes: initialFreezes)
    }

    var level: Int { Level.level(for: totalXP) }

    /// Local-calendar day index — increments by exactly 1 per calendar day
    /// regardless of DST. (Epoch/86400 division would miscount the ±1h DST
    /// boundary days, spuriously burning a freeze or resetting a streak.)
    static func dayNumber(_ date: Date, calendar: Calendar = .current) -> Int {
        calendar.ordinality(of: .day, in: .era, for: date) ?? Int(calendar.startOfDay(for: date).timeIntervalSince1970 / 86_400)
    }
}

/// The outcome of recording a catch — drives the "+XP", level-up, and streak UI.
struct ProgressEvent: Sendable {
    var xpGained: Int
    var totalXP: Int
    var leveledUpTo: Int?
    var streak: Int
    var streakExtended: Bool
    var usedFreeze: Bool
}
