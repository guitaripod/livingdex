import Foundation

/// Real-scarcity rarity tier (computed from occurrence density + conservation
/// status server-side; stored per sighting). Ordered.
public enum Rarity: String, Codable, Sendable, CaseIterable, Comparable {
    case common, uncommon, rare, epic, legendary

    private var order: Int { Rarity.allCases.firstIndex(of: self) ?? 0 }

    public static func < (lhs: Rarity, rhs: Rarity) -> Bool { lhs.order < rhs.order }
}
