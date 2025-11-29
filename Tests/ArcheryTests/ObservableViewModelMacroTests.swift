import ArcheryMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(ArcheryMacros)
private let testMacros: [String: Macro.Type] = ["ObservableViewModel": ObservableViewModelMacro.self]
#endif

@MainActor
final class ObservableViewModelMacroTests: XCTestCase {
    func testExpandsWithAsyncLoadAndHelpers() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @ObservableViewModel
            @MainActor
            class SampleVM: Resettable {
                func load() async {}
            }
            """,
            expandedSource: snapshot("ArcheryMacros/ObservableViewModel/observable_with_load"),
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }

    func testAddsLoadStubWhenMissingAndIncludesStateHelpers() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @ObservableViewModel
            @MainActor
            class NoLoadVM: Resettable {
                @ObservationTracked
                var items: LoadState<[String]> = .idle
            }
            """,
            expandedSource: snapshot("ArcheryMacros/ObservableViewModel/observable_no_load"),
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }

    func testDiagnosticsRequireMainActorAndResettable() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @ObservableViewModel
            class BadVM {}
            """,
            expandedSource: snapshot("ArcheryMacros/ObservableViewModel/observable_bad_vm"),
            diagnostics: [
                DiagnosticSpec(message: "@ObservableViewModel requires the class to be annotated with @MainActor", line: 1, column: 1),
                DiagnosticSpec(message: "@ObservableViewModel requires the class to conform to Resettable", line: 1, column: 1)
            ],
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }
}
