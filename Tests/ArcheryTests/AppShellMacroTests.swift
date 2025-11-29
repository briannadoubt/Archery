import ArcheryMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(ArcheryMacros)
private let testMacros: [String: Macro.Type] = ["AppShell": AppShellMacro.self]
#endif

@MainActor
final class AppShellMacroTests: XCTestCase {
    func testMinimalShellExpansion() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @AppShell
            struct MiniShell {
                enum Tab: CaseIterable { case home }
            }
            """,
            expandedSource: snapshot("ArcheryMacros/AppShell/appshell_minimal"),
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }

    func testDiagnosticsWhenMissingTabEnum() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @AppShell
            struct Broken {}
            """,
            expandedSource: """
            struct Broken {}
            """,
            diagnostics: [
                DiagnosticSpec(message: "@AppShell requires a nested Tab enum conforming to CaseIterable", line: 1, column: 1)
            ],
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }
}
