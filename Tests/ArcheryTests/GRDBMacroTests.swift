import Archery
import ArcheryMacros
import Foundation
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(ArcheryMacros)
private let persistableMacros: [String: Macro.Type] = [
    "Persistable": PersistableMacro.self,
    "PrimaryKey": PrimaryKeyMacro.self,
    "Indexed": IndexedMacro.self,
    "Unique": UniqueMacro.self,
    "ForeignKey": ForeignKeyMacro.self,
    "CreatedAt": CreatedAtMacro.self,
    "UpdatedAt": UpdatedAtMacro.self,
    "NotPersisted": NotPersistedMacro.self,
    "Default": DefaultMacro.self
]
private let repositoryMacros: [String: Macro.Type] = [
    "DatabaseRepository": DatabaseRepositoryMacro.self,
    "GRDBRepository": DatabaseRepositoryMacro.self
]
#endif

@MainActor
final class GRDBMacroTests: XCTestCase {

    // MARK: - @Persistable Tests

    func testPersistableMacroExpansion() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @Persistable(table: "players")
            struct Player: Codable, Identifiable {
                var id: Int64
                var name: String
                var score: Int
            }
            """,
            expandedSource: snapshot("ArcheryMacros/GRDB/persistable_basic"),
            macros: persistableMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }

    func testPersistableWithDefaultTableName() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @Persistable
            struct Task: Codable, Identifiable {
                var id: UUID
                var title: String
                var completed: Bool
            }
            """,
            expandedSource: snapshot("ArcheryMacros/GRDB/persistable_default_table"),
            macros: persistableMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }

    func testPersistableWithSchemaAttributes() throws {
        #if canImport(ArcheryMacros)
        // Test that @Persistable with schema attributes generates createTableMigration
        // This test verifies the new auto-migration feature
        assertMacroExpansion(
            """
            @Persistable(table: "tasks")
            struct Task: Codable, FetchableRecord, PersistableRecord {
                @PrimaryKey var id: String
                var title: String
                @Indexed var status: String
                @Indexed var dueDate: Date?
                @CreatedAt var createdAt: Date
                @UpdatedAt var updatedAt: Date
                @NotPersisted var isSelected: Bool = false
            }
            """,
            expandedSource: snapshot("ArcheryMacros/GRDB/persistable_schema_attrs"),
            macros: persistableMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }

    func testPersistableWithForeignKey() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @Persistable(table: "comments")
            struct Comment: Codable, FetchableRecord, PersistableRecord {
                @PrimaryKey var id: String
                var content: String
                @ForeignKey(Post.self) @Indexed var postId: String?
                @CreatedAt var createdAt: Date
            }
            """,
            expandedSource: snapshot("ArcheryMacros/GRDB/persistable_foreign_key"),
            macros: persistableMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }

    // MARK: - @GRDBRepository Tests

    func testGRDBRepositoryMacroExpansion() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @GRDBRepository(record: Player.self)
            class PlayerStore {
            }
            """,
            expandedSource: snapshot("ArcheryMacros/GRDB/repository_basic"),
            macros: repositoryMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }

    func testGRDBRepositoryWithCustomMethods() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @GRDBRepository(record: Player.self)
            class PlayerStore {
                func topScorers(limit: Int) async throws -> [Player] {
                    fatalError("Implemented by generated Live class")
                }
            }
            """,
            expandedSource: snapshot("ArcheryMacros/GRDB/repository_custom_methods"),
            macros: repositoryMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }

    func testGRDBRepositoryPublicAccess() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @GRDBRepository(record: Player.self)
            public class PlayerStore {
            }
            """,
            expandedSource: snapshot("ArcheryMacros/GRDB/repository_public"),
            macros: repositoryMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }

    func testGRDBRepositoryRequiresClass() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @GRDBRepository(record: Player.self)
            struct PlayerStore {
            }
            """,
            expandedSource: """
            struct PlayerStore {
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@DatabaseRepository can only be applied to a class", line: 1, column: 1, severity: .error)
            ],
            macros: repositoryMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }
}
