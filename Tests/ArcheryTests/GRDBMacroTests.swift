import Archery
import ArcheryMacros
import Foundation
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(ArcheryMacros)
private let persistableMacros: [String: Macro.Type] = ["Persistable": PersistableMacro.self]
private let repositoryMacros: [String: Macro.Type] = ["GRDBRepository": GRDBRepositoryMacro.self]
#endif

@MainActor
final class GRDBMacroTests: XCTestCase {

    // MARK: - @Persistable Tests

    func testPersistableMacroExpansion() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            struct Player: Codable, Identifiable {
                var id: Int64
                var name: String
                var score: Int
            }

            @Persistable(table: "players")
            extension Player {}
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
            struct Task: Codable, Identifiable {
                var id: UUID
                var title: String
                var completed: Bool
            }

            @Persistable
            extension Task {}
            """,
            expandedSource: snapshot("ArcheryMacros/GRDB/persistable_default_table"),
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
                DiagnosticSpec(message: "@GRDBRepository can only be applied to a class", line: 1, column: 1, severity: .error)
            ],
            macros: repositoryMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }
}
