import Foundation

/// XP awarded for a catch. New species are the big beats (rarity-weighted);
/// repeats give a small trickle so revisiting is still rewarded.
public enum XP {
    public static func award(rarity: Rarity, isNew: Bool) -> Int {
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
public enum Level {
    /// Total XP required to *reach* the start of a given level (level 1 == 0). The curve is a gentle quadratic ramp:
    /// 100, then +150, +200 and so on, cumulative.
    public static func threshold(_ level: Int) -> Int {
        guard level > 1 else { return 0 }
        var total = 0
        for l in 1..<level { total += 100 + (l - 1) * 50 }
        return total
    }

    /// The level for a given total XP (1-indexed).
    public static func level(for xp: Int) -> Int {
        var level = 1
        while xp >= threshold(level + 1) { level += 1 }
        return level
    }

    /// Progress within the current level: (level, xpIntoLevel, xpForThisLevel).
    public static func progress(for xp: Int) -> (level: Int, into: Int, span: Int) {
        let level = level(for: xp)
        let base = threshold(level)
        let next = threshold(level + 1)
        return (level, xp - base, max(1, next - base))
    }
}
