import ArcheryMacros
import Foundation
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import XCTest

private struct SnapshotCase {
    let name: String
    let source: String
    let macros: [String: Macro.Type]
}

private let archeryMacros: [String: Macro.Type] = [
    "ObservableViewModel": ObservableViewModelMacro.self,
    "ViewModelBound": ViewModelBoundMacro.self,
    "KeyValueStore": KeyValueStoreMacro.self,
    "DatabaseRepository": DatabaseRepositoryMacro.self,
    "AppShell": AppShellMacro.self,
    "APIClient": APIClientMacro.self,
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

@MainActor
final class SnapshotRecorder: XCTestCase {
    func testRecordSnapshotsWhenEnabled() throws {
        recordSnapshotsIfNeeded()
    }
}

private let cases: [SnapshotCase] = [
    SnapshotCase(
        name: "ArcheryMacros/ObservableViewModel/observable_with_load",
        source: """
        @ObservableViewModel
        @MainActor
        class SampleVM: Resettable {
            func load() async {}
        }
        """,
        macros: archeryMacros
    ),
    SnapshotCase(
        name: "ArcheryMacros/ObservableViewModel/observable_no_load",
        source: """
        @ObservableViewModel
        @MainActor
        class NoLoadVM: Resettable {
            @ObservationTracked
            var items: LoadState<[String]> = .idle
        }
        """,
        macros: archeryMacros
    ),
    SnapshotCase(
        name: "ArcheryMacros/ObservableViewModel/observable_bad_vm",
        source: """
        @ObservableViewModel
        class BadVM {}
        """,
        macros: archeryMacros
    ),
    SnapshotCase(
        name: "ArcheryMacros/ViewModelBound/vmbound_stateobject_autoload",
        source: """
        @ViewModelBound<SampleVM>
        struct SampleView {}
        """,
        macros: archeryMacros
    ),
    SnapshotCase(
        name: "ArcheryMacros/ViewModelBound/vmbound_custom_preview_container",
        source: """
        @ViewModelBound<SampleVM>
        struct SampleView {
            static func makePreviewContainer() -> EnvContainer { EnvContainer() }
        }
        """,
        macros: archeryMacros
    ),
    SnapshotCase(
        name: "ArcheryMacros/ViewModelBound/vmbound_observedobject_no_autoload",
        source: """
        @ViewModelBound<SampleVM>(useStateObject: false, autoLoad: false)
        struct SampleView {}
        """,
        macros: archeryMacros
    ),
    SnapshotCase(
        name: "ArcheryMacros/KeyValueStore/kvstore_basic",
        source: """
        @KeyValueStore
        enum UserStore {
            case username(String)
            case score(Int)
        }
        """,
        macros: archeryMacros
    ),
    SnapshotCase(
        name: "ArcheryMacros/AppShell/appshell_minimal",
        source: """
        @AppShell
        struct MiniShell {
            enum Tab: CaseIterable { case home }
        }
        """,
        macros: archeryMacros
    ),
    SnapshotCase(
        name: "ArcheryMacros/APIClient/apiclient_basic",
        source: """
        @APIClient
        class WeatherAPI {
            func forecast(city: String) async throws -> Data { Data() }
        }
        """,
        macros: archeryMacros
    ),
    SnapshotCase(
        name: "ArcheryMacros/APIClient/apiclient_sync_warning",
        source: """
        @APIClient
        class SyncAPI {
            func ping() -> Bool { true }
        }
        """,
        macros: archeryMacros
    ),
    SnapshotCase(
        name: "ArcheryMacros/APIClient/apiclient_cache_override",
        source: """
        @APIClient
        class CacheyAPI {
            @Cache(ttl: .seconds(5))
            func foo(id: Int) async throws -> String { "ok" }
        }
        """,
        macros: archeryMacros
    ),
    SnapshotCase(
        name: "ArcheryMacros/GRDB/persistable_basic",
        source: """
        @Persistable(table: "players")
        struct Player: Codable, Identifiable {
            var id: Int64
            var name: String
            var score: Int
        }
        """,
        macros: archeryMacros
    ),
    SnapshotCase(
        name: "ArcheryMacros/GRDB/persistable_default_table",
        source: """
        @Persistable
        struct Task: Codable, Identifiable {
            var id: UUID
            var title: String
            var completed: Bool
        }
        """,
        macros: archeryMacros
    ),
    SnapshotCase(
        name: "ArcheryMacros/GRDB/repository_basic",
        source: """
        @DatabaseRepository(record: Player.self)
        class PlayerStore {
        }
        """,
        macros: archeryMacros
    ),
    SnapshotCase(
        name: "ArcheryMacros/GRDB/repository_custom_methods",
        source: """
        @DatabaseRepository(record: Player.self)
        class PlayerStore {
            func topScorers(limit: Int) async throws -> [Player] {
                fatalError("Implemented by generated Live class")
            }
        }
        """,
        macros: archeryMacros
    ),
    SnapshotCase(
        name: "ArcheryMacros/GRDB/repository_public",
        source: """
        @DatabaseRepository(record: Player.self)
        public class PlayerStore {
        }
        """,
        macros: archeryMacros
    )
]

@MainActor private var didRecordSnapshots = false

@MainActor
func recordSnapshotsIfNeeded() {
    guard ProcessInfo.processInfo.environment["ARCHERY_RECORD_SNAPSHOTS"] == "1" else { return }
    guard !didRecordSnapshots else { return }
    didRecordSnapshots = true

    do {
        for item in cases {
            let expanded = try expand(item.source, macros: item.macros)
            try writeSnapshot(name: item.name, contents: expanded)
        }
    } catch {
        fatalError("Recording snapshots failed: \(error)")
    }
}

private func expand(_ source: String, macros: [String: Macro.Type]) throws -> String {
    let file = Parser.parse(source: source)
    let specs = macros.mapValues { MacroSpec(type: $0) }
    let context = BasicMacroExpansionContext(
        sourceFiles: [file: .init(moduleName: "ArcherySnapshots", fullFilePath: "input.swift")]
    )
    func contextGenerator(_ syntax: Syntax) -> BasicMacroExpansionContext {
        BasicMacroExpansionContext(sharingWith: context, lexicalContext: syntax.allMacroLexicalContexts())
    }

    let expanded = file.expand(
        macroSpecs: specs,
        contextGenerator: contextGenerator,
        indentationWidth: .spaces(4)
    )

    let description = expanded.description
        .drop(while: { $0.isNewline })
        .droppingLast(while: { $0.isNewline })

    return String(description)
}

private func writeSnapshot(name: String, contents: String) throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let path = root
        .appendingPathComponent("Tests")
        .appendingPathComponent("ArcheryTests")
        .appendingPathComponent("__Snapshots__")
        .appendingPathComponent(name)
        .appendingPathExtension("txt")

    try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: path, atomically: true, encoding: .utf8)
}
