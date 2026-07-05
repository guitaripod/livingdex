import Foundation
import GRDB

/// Reads and advances the player's progression (XP, level, daily streak) in one
/// transaction per catch. Streak continuity uses a local-calendar day index; a
/// one-day gap is absorbed by a freeze when available so a single missed day
/// doesn't punish the player (Duolingo-style, never punitive).
final class ProgressStore: Sendable {
    static let shared = ProgressStore()

    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    func current() throws -> PlayerProgress {
        try dbQueue.read { db in
            try PlayerProgress.fetchOne(db, key: PlayerProgress.singletonID) ?? .initial()
        }
    }

    /// Records a catch and returns what changed, for the celebration UI.
    func record(rarity: Rarity, isNew: Bool, now: Date = Date()) throws -> ProgressEvent {
        try dbQueue.write { db in
            var progress = try PlayerProgress.fetchOne(db, key: PlayerProgress.singletonID) ?? .initial()

            let previousLevel = progress.level
            let gained = XP.award(rarity: rarity, isNew: isNew)
            progress.totalXP += gained

            let today = PlayerProgress.dayNumber(now)
            var streakExtended = false
            var usedFreeze = false

            switch progress.lastCatchDay {
            case .none:
                progress.currentStreak = 1
                streakExtended = true
            case .some(let last) where last == today:
                break // already caught today — streak already counts
            case .some(let last) where today - last == 1:
                progress.currentStreak += 1
                streakExtended = true
            case .some(let last) where today - last == 2 && progress.freezes > 0:
                progress.freezes -= 1
                progress.currentStreak += 1
                streakExtended = true
                usedFreeze = true
            default:
                progress.currentStreak = 1 // gap too large — fresh streak
            }

            progress.lastCatchDay = today
            progress.longestStreak = max(progress.longestStreak, progress.currentStreak)
            try progress.save(db)

            let newLevel = progress.level
            return ProgressEvent(
                xpGained: gained,
                totalXP: progress.totalXP,
                leveledUpTo: newLevel > previousLevel ? newLevel : nil,
                streak: progress.currentStreak,
                streakExtended: streakExtended,
                usedFreeze: usedFreeze)
        }
    }
}
