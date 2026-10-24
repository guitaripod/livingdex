import Foundation

/// Top-level branch of the tree of life — the dex "realms".
public enum Realm: String, Codable, Sendable, CaseIterable {
    case animals, plants, fungi, protists, other
}
