import Archery
import ArcheryMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(ArcheryMacros)
private let testMacros: [String: Macro.Type] = ["KeyValueStore": KeyValueStoreMacro.self]
#endif

final class KeyValueStoreMacroTests: XCTestCase {
    func testExpansionProducesStoreHelpers() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @KeyValueStore
            enum UserStore {
                case username(String)
                case score(Int)
            }
            """,
            expandedSource: """
            enum UserStore {
                case username(String)
                case score(Int)

                var keyName: String {
                    switch self {
                    case .username:
                        return "UserStore.username"
                    case .score:
                        return "UserStore.score"
                    }
                }

                struct Store {
                    private var storage: [String: Data] = [:]
                    private let encoder = JSONEncoder()
                    private let decoder = JSONDecoder()
                    private let migrations: [String: String]
                    private var changeContinuation: AsyncStream<Change>.Continuation?

                    struct Change {
                        let key: UserStore
                        let data: Data?
                    }

                    init(initialValues: [String: Data] = [:], migrations: [String: String] = [:]) {
                        self.storage = initialValues
                        self.migrations = migrations
                        applyMigrations()
                    }

                    mutating func set(_ key: UserStore) async throws {
                        switch key {
                        case .username(let value):
                            storage["UserStore.username"] = try encoder.encode(value)
                            notify(key: key)
                        case .score(let value):
                            storage["UserStore.score"] = try encoder.encode(value)
                            notify(key: key)
                        }
                    }

                    func get<T: Codable>(_ key: UserStore, as type: T.Type = T.self, default defaultValue: T? = nil) async throws -> T? {
                        guard let data = storage[key.keyName] else {
                            return defaultValue
                        }
                        return try decoder.decode(T.self, from: data)
                    }

                    mutating func remove(_ key: UserStore) async {
                        storage[key.keyName] = nil
                        notify(key: key)
                    }

                    mutating func migrate(_ mapping: [String: String]) {
                        for (old, new) in mapping {
                            if let data = storage.removeValue(forKey: old) {
                                storage[new] = data
                            }
                        }
                    }

                    mutating func changes() -> AsyncStream<Change> {
                        var captured: AsyncStream<Change>.Continuation!
                        let stream = AsyncStream<Change> { continuation in
                            captured = continuation
                        }
                        self.changeContinuation = captured
                        return stream
                    }

                    private mutating func applyMigrations() {
                        migrate(migrations)
                    }

                    private func notify(key: UserStore) {
                        if let continuation = changeContinuation {
                            continuation.yield(Change(key: key, data: storage[key.keyName]))
                        }
                    }

                    func username(default defaultValue: String? = nil) async throws -> String? {
                        guard let data = storage["UserStore.username"] else {
                            return defaultValue
                        }
                        return try decoder.decode(String.self, from: data)
                    }
                    func score(default defaultValue: Int? = nil) async throws -> Int? {
                        guard let data = storage["UserStore.score"] else {
                            return defaultValue
                        }
                        return try decoder.decode(Int.self, from: data)
                    }

                    mutating func setUsername(_ value: String) async throws {
                        storage["UserStore.username"] = try encoder.encode(value)
                        notify(key: .username(value))
                    }
                    mutating func setScore(_ value: Int) async throws {
                        storage["UserStore.score"] = try encoder.encode(value)
                        notify(key: .score(value))
                    }
                }
            }
            """,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }

    @KeyValueStore
    enum RuntimeStore {
        case username(String)
        case score(Int)
    }

    func testMigrationMovesOldKeys() async throws {
        let legacy = try JSONEncoder().encode("old-name")
        let store = RuntimeStore.Store(
            initialValues: ["RuntimeStore.name": legacy],
            migrations: ["RuntimeStore.name": "RuntimeStore.username"]
        )

        let migrated = try await store.username()
        XCTAssertEqual(migrated, "old-name")
    }

    func testDefaultValueReturnedWhenMissing() async throws {
        let store = RuntimeStore.Store()
        let value = try await store.username(default: "guest")
        XCTAssertEqual(value, "guest")
    }

    func testChangeNotificationsYieldUpdates() async throws {
        var store = RuntimeStore.Store()
        let stream = store.changes()
        var iterator = stream.makeAsyncIterator()

        try await store.set(.score(42))

        let change = await iterator.next()
        XCTAssertNotNil(change)
        XCTAssertEqual(change?.key.keyName, "RuntimeStore.score")

        if let data = change?.data {
            let decoded = try JSONDecoder().decode(Int.self, from: data)
            XCTAssertEqual(decoded, 42)
        } else {
            XCTFail("Expected data for change")
        }
    }
}
