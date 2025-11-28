import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

enum ObservableViewModelDiagnostic: String, DiagnosticMessage {
    case mustBeClass

    var message: String {
        switch self {
        case .mustBeClass: return "@ObservableViewModel can only be applied to a class"
        }
    }
    var diagnosticID: MessageID { .init(domain: "ArcheryMacros", id: rawValue) }
    var severity: DiagnosticSeverity { .error }
}

public enum ObservableViewModelMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(ClassDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .mustBeClass)])
        }

        let resetDecl = """
@MainActor
func reset() {
    cancelTrackedTasks()
}
"""

        let onAppearDecl = """
@MainActor
func onAppear() {
}
"""

        let onDisappearDecl = """
@MainActor
func onDisappear() {
    cancelTrackedTasks()
}
"""

        let trackDecl = """
@MainActor
func track(_ task: CancelableTask) {
    __archeryCancelables.append(task)
}
"""

        let cancelDecl = """
@MainActor
func cancelTrackedTasks() {
    __archeryCancelables.forEach { $0.cancel() }
    __archeryCancelables.removeAll()
}
"""

        let storageDecl = """
@MainActor
private var __archeryCancelables: [CancelableTask] = []
"""

        return [
            DeclSyntax(stringLiteral: storageDecl),
            DeclSyntax(stringLiteral: trackDecl),
            DeclSyntax(stringLiteral: cancelDecl),
            DeclSyntax(stringLiteral: resetDecl),
            DeclSyntax(stringLiteral: onAppearDecl),
            DeclSyntax(stringLiteral: onDisappearDecl)
        ]
    }

    private static func diagnostic(for node: some SyntaxProtocol, kind: ObservableViewModelDiagnostic) -> Diagnostic {
        Diagnostic(node: Syntax(node), message: kind)
    }
}
