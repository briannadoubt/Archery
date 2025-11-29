import Archery
import XCTest

@PersistenceGateway
enum PersistenceRuntimeStore {
    case username(String)
    case score(Int)
}

@MainActor
final class PersistenceRuntimeTests: XCTestCase {
    func testSeedsLoadFromInMemoryStore() async throws {
        let seeds: [PersistenceRuntimeStore.Gateway.Seed] = [(.username("Robin"), "Robin")]
        let gateway = try PersistenceRuntimeStore.Gateway(inMemory: seeds)
        let value = try await gateway.username()
        XCTAssertEqual(value, "Robin")
    }

    func testMigrationRenamesKey() async throws {
        // Create legacy database without migrations
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("archery-persistence-test.sqlite")
        try? FileManager.default.removeItem(at: tmp)

        let legacyStore = try SQLiteKVStore(
            url: tmp,
            migrations: [],
            seed: ["legacy.username": try JSONEncoder().encode("Legacy")]
        )
        _ = legacyStore // keep alive

        let migration = SQLiteMigration(fromVersion: 0, toVersion: 1) { rows in
            var copy = rows
            if let data = copy.removeValue(forKey: "legacy.username") {
                copy["PersistenceRuntimeStore.username"] = data
            }
            return copy
        }

        let migrated = try PersistenceRuntimeStore.Gateway(url: tmp, migrations: [migration])
        let value = try await migrated.username()
        XCTAssertEqual(value, "Legacy")
    }

    func testCrudRoundTrip() async throws {
        let gateway = try PersistenceRuntimeStore.Gateway(inMemory: [])
        try await gateway.set(.score(42))
        let fetched = try await gateway.score()
        XCTAssertEqual(fetched, 42)
        try await gateway.remove(.score(42))
        let removed = try await gateway.score()
        XCTAssertNil(removed)
    }
}
