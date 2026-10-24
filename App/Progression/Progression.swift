import Foundation
import GRDB
import LivingDexCore

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

    /// A fixed UTC calendar. Using a stable timezone (not `.current`) means a
    /// stored `lastCatchDay` keeps its meaning across timezone changes: the day
    /// index of a real-time-later catch is always ≥ the stored one, so westward
    /// travel can't reset an intact streak and eastward travel can't inflate the
    /// gap and spuriously burn a freeze. UTC has no DST, so per-day ordinality
    /// still increments by exactly 1.
    static let streakCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Timezone-stable day index — increments by exactly 1 per UTC calendar day.
    static func dayNumber(_ date: Date, calendar: Calendar = streakCalendar) -> Int {
        calendar.ordinality(of: .day, in: .era, for: date) ?? Int(calendar.startOfDay(for: date).timeIntervalSince1970 / 86_400)
    }
}
