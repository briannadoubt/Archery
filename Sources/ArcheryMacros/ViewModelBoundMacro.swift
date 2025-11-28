import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

enum ViewModelBoundDiagnostic: String, DiagnosticMessage {
    case mustBeStruct
    case missingType

    var message: String {
        switch self {
        case .mustBeStruct: return "@ViewModelBound can only be applied to a struct"
        case .missingType: return "@ViewModelBound requires a ViewModel type"
        }
    }

    var diagnosticID: MessageID { .init(domain: "ArcheryMacros", id: rawValue) }
    var severity: DiagnosticSeverity { .error }
}

public enum ViewModelBoundMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .mustBeStruct)])
        }

        guard let typeName = extractType(from: node) else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .missingType)])
        }

        let holderName = "__ArcheryVMHolder"

        let storage = """
@SwiftUI.Environment(\\.archeryContainer) private var __archeryEnv
@StateObject private var vmHolder = \(holderName)(container: __archeryEnv)
"""

        let computed = """
var vm: \(typeName) { vmHolder.value }
"""

        let holder = """
private final class \(holderName): ObservableObject {
    let value: \(typeName)
    init(container: EnvContainer?, factory: @escaping () -> \(typeName) = { \(typeName)() }) {
        if let resolved: \(typeName) = container?.resolve() {
            self.value = resolved
        } else {
            self.value = factory()
        }
    }
}
"""

        return [DeclSyntax(stringLiteral: storage), DeclSyntax(stringLiteral: computed), DeclSyntax(stringLiteral: holder)]
    }

    private static func extractType(from node: AttributeSyntax) -> String? {
        if let generic = node.attributeName.as(IdentifierTypeSyntax.self)?.genericArgumentClause?.arguments.first?.argument {
            return generic.trimmedDescription
        }
        if let args = node.arguments?.as(LabeledExprListSyntax.self), let first = args.first {
            return first.expression.trimmedDescription
        }
        return nil
    }

    private static func diagnostic(for node: some SyntaxProtocol, kind: ViewModelBoundDiagnostic) -> Diagnostic {
        Diagnostic(node: Syntax(node), message: kind)
    }
}

private extension SyntaxProtocol {
    var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
}
