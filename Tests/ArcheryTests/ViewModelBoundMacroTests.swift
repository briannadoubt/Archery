#if os(macOS)
import ArcheryMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

private let testMacros: [String: Macro.Type] = ["ViewModelBound": ViewModelBoundMacro.self]

@MainActor
final class ViewModelBoundMacroTests: XCTestCase {
    func testInjectsStateViewModel() throws {
        assertMacroExpansion(
            """
            @ViewModelBound<SampleVM>
            struct SampleView {}
            """,
            expandedSource: snapshot("ArcheryMacros/ViewModelBound/vmbound_stateobject_autoload"),
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testUsesCustomPreviewContainerWhenPresent() throws {
        assertMacroExpansion(
            """
            @ViewModelBound<SampleVM>
            struct SampleView {
                static func makePreviewContainer() -> EnvContainer { EnvContainer() }
            }
            """,
            expandedSource: snapshot("ArcheryMacros/ViewModelBound/vmbound_custom_preview_container"),
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testObservedObjectAndNoAutoLoad() throws {
        assertMacroExpansion(
            """
            @ViewModelBound<SampleVM>(useStateObject: false, autoLoad: false)
            struct SampleView {}
            """,
            expandedSource: snapshot("ArcheryMacros/ViewModelBound/vmbound_observedobject_no_autoload"),
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }
}
#endif
