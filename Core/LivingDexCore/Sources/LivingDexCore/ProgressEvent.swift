import Foundation

/// The outcome of recording a catch — drives the "+XP", level-up, and streak UI.
public struct ProgressEvent: Sendable {
    public var xpGained: Int
    public var totalXP: Int
    public var leveledUpTo: Int?
    public var streak: Int
    public var streakExtended: Bool
    public var usedFreeze: Bool

    public init(xpGained: Int, totalXP: Int, leveledUpTo: Int?, streak: Int, streakExtended: Bool, usedFreeze: Bool) {
        self.xpGained = xpGained
        self.totalXP = totalXP
        self.leveledUpTo = leveledUpTo
        self.streak = streak
        self.streakExtended = streakExtended
        self.usedFreeze = usedFreeze
    }
}
