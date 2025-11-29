import Archery
import ArcheryMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(ArcheryMacros)
private let testMacros: [String: Macro.Type] = ["KeyValueStore": KeyValueStoreMacro.self]
#endif

@MainActor
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
            expandedSource: snapshot("ArcheryMacros/KeyValueStore/kvstore_basic"),
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }

    func testDiagnosticsRequireAssociatedValues() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @KeyValueStore
            enum BadStore {
                case username
            }
            """,
            expandedSource: """
            enum BadStore {
                case username
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "Each case must have a single associated value", line: 3, column: 5, severity: .error)
            ],
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
