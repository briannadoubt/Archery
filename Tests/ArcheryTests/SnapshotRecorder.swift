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
    "Repository": RepositoryMacro.self,
    "AppShell": AppShellMacro.self
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
        name: "ArcheryMacros/Repository/repo_basic",
        source: """
        @Repository
        class UserRepository {
            func profile(id: Int) async throws -> String { "ok" }
        }
        """,
        macros: archeryMacros
    ),
    SnapshotCase(
        name: "ArcheryMacros/Repository/repo_sync_warning",
        source: """
        @Repository
        class SyncRepository {
            func profile(id: Int) -> String { "ok" }
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
