import Archery
import Foundation
import GRDB
import XCTest

// Disambiguate from GRDB.PersistenceContainer
typealias DBContainer = Archery.PersistenceContainer

// MARK: - Test Model

/// A simple test record for GRDB operations
struct TestPlayer: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var name: String
    var score: Int
    var team: String?
    var createdAt: Date

    static let databaseTableName = "test_players"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let score = Column(CodingKeys.score)
        static let team = Column(CodingKeys.team)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, score, team
        case createdAt = "created_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Test Migrations

private let testMigrations = MigrationRunner {
    Migration(id: "v1_create_test_players") { db in
        try db.create(table: "test_players") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("score", .integer).notNull().defaults(to: 0)
            t.column("team", .text)
            t.column("created_at", .datetime).notNull()
        }
    }

    Migration(id: "v2_add_team_index") { db in
        try db.create(index: "test_players_team_idx", on: "test_players", columns: ["team"])
    }
}

// MARK: - DBContainer Tests

final class DBContainerTests: XCTestCase {

    func testInMemoryDatabaseCreation() throws {
        let container = try DBContainer.inMemory()
        XCTAssertNotNil(container.writer)
    }

    func testReadWriteOperations() async throws {
        let container = try DBContainer.inMemory()

        // Run migrations first
        try testMigrations.run(on: container)

        // Write a record
        let player = try await container.write { db -> TestPlayer in
            var p = TestPlayer(name: "Alice", score: 100, team: "Blue", createdAt: Date())
            try p.insert(db)
            return p
        }

        XCTAssertNotNil(player.id)
        XCTAssertEqual(player.name, "Alice")

        // Read it back
        let fetched = try await container.read { db in
            try TestPlayer.fetchOne(db, id: player.id!)
        }

        XCTAssertEqual(fetched?.name, "Alice")
        XCTAssertEqual(fetched?.score, 100)
    }

    func testEnvContainerIntegration() throws {
        let grdbContainer = try DBContainer.inMemory()
        let envContainer = EnvContainer()

        envContainer.registerGRDB(grdbContainer)

        XCTAssertNotNil(envContainer.grdb)
        XCTAssertTrue(envContainer.grdb === grdbContainer)
    }
}

// MARK: - GRDBMigration Tests

final class MigrationTests: XCTestCase {

    func testMigrationRunner() throws {
        let container = try DBContainer.inMemory()

        // Run migrations
        try testMigrations.run(on: container)

        // Verify table was created
        let tableExists = try container.writer.read { db in
            try db.tableExists("test_players")
        }
        XCTAssertTrue(tableExists)
    }

    func testMigrationWithDatabaseWriter() throws {
        let queue = try DatabaseQueue()

        try testMigrations.run(on: queue)

        let tableExists = try queue.read { db in
            try db.tableExists("test_players")
        }
        XCTAssertTrue(tableExists)
    }

    func testHasPendingMigrations() throws {
        let container = try DBContainer.inMemory()

        // Before running, should have pending migrations
        let hasPendingBefore = try testMigrations.hasPendingMigrations(on: container.writer)
        XCTAssertTrue(hasPendingBefore)

        // Run migrations
        try testMigrations.run(on: container)

        // After running, should have no pending migrations
        let hasPendingAfter = try testMigrations.hasPendingMigrations(on: container.writer)
        XCTAssertFalse(hasPendingAfter)
    }

    func testMigrationHelpers() throws {
        let container = try DBContainer.inMemory()

        // Test createTable helper
        let createMigration = Migration.createTable(id: "create_items", for: TestPlayer.self) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("score", .integer).notNull()
            t.column("team", .text)
            t.column("created_at", .datetime).notNull()
        }

        let runner = MigrationRunner([createMigration])
        try runner.run(on: container)

        let tableExists = try container.writer.read { db in
            try db.tableExists("test_players")
        }
        XCTAssertTrue(tableExists)
    }

    func testAddColumnMigration() throws {
        let container = try DBContainer.inMemory()

        // First create a simple table
        let migrations = MigrationRunner {
            Migration(id: "v1_create") { db in
                try db.create(table: "items") { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("name", .text).notNull()
                }
            }

            Migration.addColumn(
                id: "v2_add_description",
                table: "items",
                column: "description",
                type: .text
            )
        }

        try migrations.run(on: container)

        // Verify column exists by inserting with it
        try container.writer.write { db in
            try db.execute(sql: "INSERT INTO items (name, description) VALUES (?, ?)", arguments: ["Test", "A description"])
        }

        let count = try container.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM items")
        }
        XCTAssertEqual(count, 1)
    }

    func testCreateIndexMigration() throws {
        let container = try DBContainer.inMemory()

        let migrations = MigrationRunner {
            Migration(id: "v1_create") { db in
                try db.create(table: "items") { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("category", .text).notNull()
                }
            }

            Migration.createIndex(
                id: "v2_category_index",
                table: "items",
                columns: ["category"]
            )
        }

        try migrations.run(on: container)

        // Verify index exists
        let indexExists = try container.writer.read { db -> Bool in
            let indexes = try Row.fetchAll(db, sql: "PRAGMA index_list('items')")
            return indexes.contains { $0["name"] as? String == "items_category_idx" }
        }
        XCTAssertTrue(indexExists)
    }

    func testRawSQLMigration() throws {
        let container = try DBContainer.inMemory()

        let migrations = MigrationRunner {
            Migration.sql(id: "v1_create_view", """
                CREATE TABLE raw_items (id INTEGER PRIMARY KEY, value TEXT);
                CREATE VIEW items_view AS SELECT * FROM raw_items WHERE value IS NOT NULL;
            """)
        }

        try migrations.run(on: container)

        // Check that the table exists (tableExists doesn't work for views)
        let tableExists = try container.writer.read { db in
            try db.tableExists("raw_items")
        }
        XCTAssertTrue(tableExists)

        // Check that the view exists using raw SQL
        let viewExists = try container.writer.read { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type='view' AND name='items_view'")
            return count == 1
        }
        XCTAssertTrue(viewExists)
    }
}

// MARK: - PersistenceError Tests

final class PersistenceErrorTests: XCTestCase {

    func testErrorNormalization() {
        // Test notFound
        let notFoundError = PersistenceError.notFound
        XCTAssertEqual(notFoundError, .notFound)

        // Test constraintViolation
        let constraintError = PersistenceError.constraintViolation("UNIQUE constraint failed")
        if case .constraintViolation(let msg) = constraintError {
            XCTAssertEqual(msg, "UNIQUE constraint failed")
        } else {
            XCTFail("Expected constraintViolation")
        }
    }

    func testNormalizePersistenceError() {
        // Test with a generic error
        struct TestError: Error {}
        let normalized = normalizePersistenceError(TestError())

        if case .unknown = normalized {
            // Expected
        } else {
            XCTFail("Expected unknown error type")
        }
    }

    func testPersistenceSourceError() {
        let underlying = PersistenceError.queryFailed("Test query failed")
        let sourceError = PersistenceSourceError(
            underlying,
            function: "testFunction",
            file: "TestFile.swift",
            line: 42
        )

        XCTAssertEqual(sourceError.function, "testFunction")
        XCTAssertEqual(sourceError.file, "TestFile.swift")
        XCTAssertEqual(sourceError.line, 42)
        XCTAssertTrue(sourceError.localizedDescription.contains("testFunction"))
        XCTAssertTrue(sourceError.localizedDescription.contains("TestFile.swift"))
        XCTAssertTrue(sourceError.localizedDescription.contains("42"))
    }
}

// MARK: - CRUD Integration Tests

final class GRDBCRUDTests: XCTestCase {

    var container: DBContainer!

    override func setUp() async throws {
        container = try DBContainer.inMemory()
        try testMigrations.run(on: container)
    }

    override func tearDown() async throws {
        container = nil
    }

    func testInsertAndFetch() async throws {
        // Insert
        let player = try await container.write { db in
            var p = TestPlayer(name: "Bob", score: 50, team: "Red", createdAt: Date())
            try p.insert(db)
            return p
        }

        XCTAssertNotNil(player.id)

        // Fetch by ID
        let playerId = player.id!
        let fetched = try await container.read { db in
            try TestPlayer.fetchOne(db, id: playerId)
        }

        XCTAssertEqual(fetched?.name, "Bob")
        XCTAssertEqual(fetched?.score, 50)
        XCTAssertEqual(fetched?.team, "Red")
    }

    func testFetchAll() async throws {
        // Insert multiple players
        try await container.write { db in
            var p1 = TestPlayer(name: "Alice", score: 100, team: "Blue", createdAt: Date())
            var p2 = TestPlayer(name: "Bob", score: 80, team: "Red", createdAt: Date())
            var p3 = TestPlayer(name: "Charlie", score: 90, team: "Blue", createdAt: Date())
            try p1.insert(db)
            try p2.insert(db)
            try p3.insert(db)
        }

        let all = try await container.read { db in
            try TestPlayer.fetchAll(db)
        }

        XCTAssertEqual(all.count, 3)
    }

    func testUpdate() async throws {
        // Insert
        let insertedPlayer = try await container.write { db in
            var p = TestPlayer(name: "Alice", score: 100, team: "Blue", createdAt: Date())
            try p.insert(db)
            return p
        }

        // Update - create updated copy and update in closure
        let playerId = insertedPlayer.id!
        var playerToUpdate = insertedPlayer
        playerToUpdate.score = 150
        playerToUpdate.team = "Green"

        try await container.write { [playerToUpdate] db in
            try playerToUpdate.update(db)
        }

        // Verify
        let updated = try await container.read { db in
            try TestPlayer.fetchOne(db, id: playerId)
        }

        XCTAssertEqual(updated?.score, 150)
        XCTAssertEqual(updated?.team, "Green")
    }

    func testDelete() async throws {
        // Insert
        let player = try await container.write { db in
            var p = TestPlayer(name: "ToDelete", score: 0, createdAt: Date())
            try p.insert(db)
            return p
        }

        // Delete
        let deleted = try await container.write { db in
            try TestPlayer.deleteOne(db, id: player.id!)
        }

        XCTAssertTrue(deleted)

        // Verify gone
        let fetched = try await container.read { db in
            try TestPlayer.fetchOne(db, id: player.id!)
        }

        XCTAssertNil(fetched)
    }

    func testDeleteAll() async throws {
        // Insert multiple
        try await container.write { db in
            for i in 1...5 {
                var p = TestPlayer(name: "Player \(i)", score: i * 10, createdAt: Date())
                try p.insert(db)
            }
        }

        // Delete all
        let deletedCount = try await container.write { db in
            try TestPlayer.deleteAll(db)
        }

        XCTAssertEqual(deletedCount, 5)

        // Verify empty
        let count = try await container.read { db in
            try TestPlayer.fetchCount(db)
        }

        XCTAssertEqual(count, 0)
    }

    func testCount() async throws {
        // Insert
        try await container.write { db in
            for i in 1...3 {
                var p = TestPlayer(name: "Player \(i)", score: i * 10, createdAt: Date())
                try p.insert(db)
            }
        }

        let count = try await container.read { db in
            try TestPlayer.fetchCount(db)
        }

        XCTAssertEqual(count, 3)
    }

    func testQueryWithColumns() async throws {
        // Insert players with different teams
        try await container.write { db in
            var p1 = TestPlayer(name: "Alice", score: 100, team: "Blue", createdAt: Date())
            var p2 = TestPlayer(name: "Bob", score: 80, team: "Red", createdAt: Date())
            var p3 = TestPlayer(name: "Charlie", score: 90, team: "Blue", createdAt: Date())
            try p1.insert(db)
            try p2.insert(db)
            try p3.insert(db)
        }

        // Query using type-safe Columns
        let bluePlayers = try await container.read { db in
            try TestPlayer
                .filter(TestPlayer.Columns.team == "Blue")
                .order(TestPlayer.Columns.score.desc)
                .fetchAll(db)
        }

        XCTAssertEqual(bluePlayers.count, 2)
        XCTAssertEqual(bluePlayers[0].name, "Alice") // Highest score first
        XCTAssertEqual(bluePlayers[1].name, "Charlie")
    }

    func testUpsert() async throws {
        // Insert initial
        let insertedPlayer = try await container.write { db in
            var p = TestPlayer(name: "Alice", score: 100, team: "Blue", createdAt: Date())
            try p.insert(db)
            return p
        }

        // Upsert with same ID (update)
        var playerToUpsert = insertedPlayer
        playerToUpsert.score = 200
        let upserted = try await container.write { [playerToUpsert] db in
            try playerToUpsert.saved(db)
        }

        XCTAssertEqual(upserted.id, insertedPlayer.id)

        // Verify updated
        let count = try await container.read { db in
            try TestPlayer.fetchCount(db)
        }
        XCTAssertEqual(count, 1) // Still only one record

        let playerId = insertedPlayer.id!
        let fetched = try await container.read { db in
            try TestPlayer.fetchOne(db, id: playerId)
        }
        XCTAssertEqual(fetched?.score, 200)
    }
}

// MARK: - Concurrency Tests

final class GRDBConcurrencyTests: XCTestCase {

    func testConcurrentReads() async throws {
        let container = try DBContainer.inMemory()
        try testMigrations.run(on: container)

        // Insert test data
        try await container.write { db in
            for i in 1...100 {
                var p = TestPlayer(name: "Player \(i)", score: i, createdAt: Date())
                try p.insert(db)
            }
        }

        // Perform concurrent reads
        await withTaskGroup(of: Int.self) { group in
            for _ in 1...10 {
                group.addTask {
                    do {
                        return try await container.read { db in
                            try TestPlayer.fetchCount(db)
                        }
                    } catch {
                        return -1
                    }
                }
            }

            for await count in group {
                XCTAssertEqual(count, 100)
            }
        }
    }

    func testSequentialWrites() async throws {
        let container = try DBContainer.inMemory()
        try testMigrations.run(on: container)

        // Perform sequential writes
        for i in 1...10 {
            try await container.write { db in
                var p = TestPlayer(name: "Player \(i)", score: i * 10, createdAt: Date())
                try p.insert(db)
            }
        }

        let count = try await container.read { db in
            try TestPlayer.fetchCount(db)
        }

        XCTAssertEqual(count, 10)
    }
}
