import Foundation
import GRDB

/// Reads/writes the player's collection. Saving a sighting upserts its
/// materialized `DexEntry` in the same transaction so the Dex grid stays
/// consistent, and `observeDex` drives the grid reactively via GRDB.
final class CollectionStore: Sendable {
    static let shared = CollectionStore()

    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    /// Persists a capture and folds it into the species' dex entry. Returns
    /// whether this was the first-ever catch of the species (a "new dex entry"
    /// — the big XP / celebration beat).
    @discardableResult
    func save(_ sighting: Sighting) throws -> Bool {
        try dbQueue.write { db in
            var s = sighting
            try s.insert(db)

            let existing = try DexEntry.fetchOne(db, key: sighting.speciesId)
            if var entry = existing {
                entry.sightingCount += 1
                entry.lastCaughtAt = sighting.capturedAt
                if sighting.capturedAt < entry.firstCaughtAt { entry.firstCaughtAt = sighting.capturedAt }
                try entry.update(db)
                return false
            } else {
                var entry = DexEntry(
                    speciesId: sighting.speciesId,
                    commonName: sighting.commonName,
                    scientificName: sighting.scientificName,
                    realm: sighting.realm,
                    rarity: sighting.rarity,
                    firstCaughtAt: sighting.capturedAt,
                    lastCaughtAt: sighting.capturedAt,
                    sightingCount: 1,
                    bestImagePath: sighting.imagePath)
                try entry.insert(db)
                return true
            }
        }
    }

    /// Emits the full dex (rarest first, then most recent) whenever it changes.
    func observeDex(onChange: @escaping @Sendable ([DexEntry]) -> Void) -> AnyDatabaseCancellable {
        let observation = ValueObservation.tracking { db in
            try DexEntry
                .order(Column("lastCaughtAt").desc)
                .fetchAll(db)
        }
        return observation.start(
            in: dbQueue,
            scheduling: .async(onQueue: .main),
            onError: { AppLogger.shared.error("dex observation error: \($0)", category: .persistence) },
            onChange: onChange)
    }

    func dexCount() throws -> Int {
        try dbQueue.read { try DexEntry.fetchCount($0) }
    }

    /// Collection summary: total unique species, total catches, and a per-rarity
    /// breakdown — the progress surface for the Profile tab.
    struct Stats: Sendable {
        var speciesCount: Int
        var totalCatches: Int
        var byRarity: [Rarity: Int]
        var realms: Set<Realm>
        var maxRarity: Rarity?
    }

    func stats() throws -> Stats {
        try dbQueue.read { db in
            let entries = try DexEntry.fetchAll(db)
            var byRarity: [Rarity: Int] = [:]
            var realms: Set<Realm> = []
            var totalCatches = 0
            for e in entries {
                byRarity[e.rarity, default: 0] += 1
                realms.insert(e.realm)
                totalCatches += e.sightingCount
            }
            let maxRarity = Rarity.allCases.last { byRarity[$0] != nil }
            return Stats(
                speciesCount: entries.count, totalCatches: totalCatches,
                byRarity: byRarity, realms: realms, maxRarity: maxRarity)
        }
    }

    /// Stores the narrated Pokédex entry (+ category and typical size) onto a
    /// sighting, filled async after capture; the card reads the latest sighting.
    func setNarration(sightingId: String, entry: PokedexEntry) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE sightings SET pokedexEntry = ?, category = ?, typicalSize = ? WHERE id = ?",
                arguments: [entry.displayText, entry.category, entry.typicalSize, sightingId])
        }
    }

    /// The most recent sighting of a species — powers the card detail (image +
    /// narration + capture metadata).
    func latestSighting(speciesId: String) throws -> Sighting? {
        try dbQueue.read { db in
            try Sighting
                .filter(Column("speciesId") == speciesId)
                .order(Column("capturedAt").desc)
                .fetchOne(db)
        }
    }
}
