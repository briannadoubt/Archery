import ArcheryMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(ArcheryMacros)
private let testMacros: [String: Macro.Type] = ["ViewModelBound": ViewModelBoundMacro.self]
#endif

final class ViewModelBoundMacroTests: XCTestCase {
    func testInjectsStateViewModel() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @ViewModelBound<SampleVM>
            struct SampleView {}
            """,
            expandedSource: """
            struct SampleView {

                @SwiftUI.Environment(\\.archeryContainer) private var __archeryEnv
                @StateObject private var vmHolder = __ArcheryVMHolder(container: __archeryEnv)

                var vm: SampleVM {
                    vmHolder.value
                }

                private final class __ArcheryVMHolder: ObservableObject {
                    let value: SampleVM
                    init(container: EnvContainer?, factory: @escaping () -> SampleVM = {
                            SampleVM()
                        }) {
                        if let resolved: SampleVM = container?.resolve() {
                            self.value = resolved
                        } else {
                            self.value = factory()
                        }
                    }
                }
            }
            """,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }
}
