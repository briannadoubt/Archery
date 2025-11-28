import ArcheryMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(ArcheryMacros)
private let testMacros: [String: Macro.Type] = ["ObservableViewModel": ObservableViewModelMacro.self]
#endif

final class ObservableViewModelMacroTests: XCTestCase {
    func testAddsResetMember() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @ObservableViewModel
            class SampleVM {}
            """,
            expandedSource: """
            class SampleVM {

                @MainActor
                private var __archeryCancelables: [CancelableTask] = []

                @MainActor
                func track(_ task: CancelableTask) {
                    __archeryCancelables.append(task)
                }

                @MainActor
                func cancelTrackedTasks() {
                    __archeryCancelables.forEach {
                        $0.cancel()
                    }
                    __archeryCancelables.removeAll()
                }

                @MainActor
                func reset() {
                    cancelTrackedTasks()
                }

                @MainActor
                func onAppear() {
                }

                @MainActor
                func onDisappear() {
                    cancelTrackedTasks()
                }
            }
            """,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }
}
