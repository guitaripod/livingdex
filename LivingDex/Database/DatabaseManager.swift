import Foundation
import GRDB

final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()

    let dbQueue: DatabaseQueue

    private init() {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = support.appendingPathComponent("livingdex", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let path = dir.appendingPathComponent("livingdex.sqlite").path
            let queue = try DatabaseQueue(path: path)
            try Self.runMigrations(queue)
            dbQueue = queue
            AppLogger.shared.info("database opened at \(path)", category: .persistence)
        } catch {
            AppLogger.shared.error("database open failed, falling back to in-memory: \(error)", category: .persistence)
            // swiftlint:disable:next force_try
            let queue = try! DatabaseQueue()
            try? Self.runMigrations(queue)
            dbQueue = queue
        }
    }

    init(inMemoryName: String) throws {
        dbQueue = try DatabaseQueue(named: inMemoryName)
        try Self.runMigrations(dbQueue)
    }

    /// Wipe all on-device collection data — used by account deletion. Schema kept.
    func eraseAllData() throws {
        try dbQueue.write { db in
            for table in ["sightings", "dex_entries"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }

    private static func runMigrations(_ db: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "sightings") { t in
                t.primaryKey("id", .text)
                t.column("speciesId", .text).notNull().indexed()
                t.column("commonName", .text).notNull()
                t.column("scientificName", .text).notNull()
                t.column("realm", .text).notNull()
                t.column("rarity", .text).notNull()
                t.column("confidence", .double).notNull()
                t.column("capturedAt", .datetime).notNull().indexed()
                t.column("latitude", .double)
                t.column("longitude", .double)
                t.column("elevationMeters", .double)
                t.column("imagePath", .text).notNull()
                t.column("pokedexEntry", .text)
            }
            try db.create(table: "dex_entries") { t in
                t.primaryKey("speciesId", .text)
                t.column("commonName", .text).notNull()
                t.column("scientificName", .text).notNull()
                t.column("realm", .text).notNull().indexed()
                t.column("rarity", .text).notNull()
                t.column("firstCaughtAt", .datetime).notNull()
                t.column("lastCaughtAt", .datetime).notNull()
                t.column("sightingCount", .integer).notNull().defaults(to: 0)
                t.column("bestImagePath", .text).notNull()
            }
        }
        migrator.registerMigration("v2_progress") { db in
            try db.create(table: "player_progress") { t in
                t.primaryKey("id", .integer)
                t.column("totalXP", .integer).notNull().defaults(to: 0)
                t.column("currentStreak", .integer).notNull().defaults(to: 0)
                t.column("longestStreak", .integer).notNull().defaults(to: 0)
                t.column("lastCatchDay", .integer)
                t.column("freezes", .integer).notNull().defaults(to: 2)
            }
            try db.execute(
                sql: "INSERT OR IGNORE INTO player_progress (id, totalXP, currentStreak, longestStreak, lastCatchDay, freezes) VALUES (?, 0, 0, 0, NULL, ?)",
                arguments: [PlayerProgress.singletonID, PlayerProgress.initialFreezes])
        }
        migrator.registerMigration("v3_species_facts") { db in
            try db.alter(table: "sightings") { t in
                t.add(column: "category", .text)
                t.add(column: "typicalSize", .text)
            }
        }
        migrator.registerMigration("v4_enriched") { db in
            try db.alter(table: "sightings") { t in
                t.add(column: "enriched", .boolean).notNull().defaults(to: false)
            }
            try db.alter(table: "dex_entries") { t in
                t.add(column: "enriched", .boolean).notNull().defaults(to: false)
            }
        }
        try migrator.migrate(db)
    }
}
