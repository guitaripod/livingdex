import Foundation
import GRDB

/// Real-scarcity rarity tier (computed from occurrence density + conservation
/// status server-side; stored per sighting). Ordered.
enum Rarity: String, Codable, Sendable, CaseIterable {
    case common, uncommon, rare, epic, legendary
}

/// Top-level branch of the tree of life — the dex "realms".
enum Realm: String, Codable, Sendable, CaseIterable {
    case animals, plants, fungi, protists, other
}

/// One capture event — the raw record. Rich card metadata is fused from the
/// sensor suite at capture time; the Claude-authored `pokedexEntry` is filled
/// asynchronously once online.
struct Sighting: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "sightings"

    var id: String
    var speciesId: String
    var commonName: String
    var scientificName: String
    var realm: Realm
    var rarity: Rarity
    var confidence: Double
    var capturedAt: Date
    var latitude: Double?
    var longitude: Double?
    var elevationMeters: Double?
    var imagePath: String
    var pokedexEntry: String?
    var category: String? = nil
    var typicalSize: String? = nil
    /// True once GBIF confirmed the species (real rarity + names). A provisional
    /// capture (saved offline) starts false and heals on a later card open.
    var enriched: Bool = false
}

/// One collected species — the materialized "dex" row, upserted on each capture
/// so the grid renders without aggregating raw sightings.
struct DexEntry: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "dex_entries"

    var id: String { speciesId }
    var speciesId: String
    var commonName: String
    var scientificName: String
    var realm: Realm
    var rarity: Rarity
    var firstCaughtAt: Date
    var lastCaughtAt: Date
    var sightingCount: Int
    var bestImagePath: String
    var enriched: Bool = false

    enum CodingKeys: String, CodingKey {
        case speciesId, commonName, scientificName, realm, rarity
        case firstCaughtAt, lastCaughtAt, sightingCount, bestImagePath, enriched
    }
}
