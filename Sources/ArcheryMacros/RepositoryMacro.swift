import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

enum RepositoryDiagnostic: String, DiagnosticMessage {
    case mustBeClass

    var message: String {
        switch self {
        case .mustBeClass: return "@Repository can only be applied to a class"
        }
    }

    var diagnosticID: MessageID { .init(domain: "ArcheryMacros", id: rawValue) }
    var severity: DiagnosticSeverity { .error }
}

public enum RepositoryMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf decl: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDecl = decl.as(ClassDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: decl, kind: .mustBeClass)])
        }

        let isPublic = classDecl.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
        let access = isPublic ? "public " : ""
        let className = classDecl.name.text
        let protocolName = "\(className)Protocol"
        let mockName = "Mock\(className)"

        let methods = classDecl.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }

        let protocolFns = methods.map { fn in
            let signature = fn.signature.description.trimmingCharacters(in: .whitespacesAndNewlines)
            return "    func \(fn.name.text)\(signature)"
        }.joined(separator: "\n")

        let mockProps = methods.map { fn in
            let handlerType = fn.handlerType
            return "    var \(fn.name.text)Handler: \(handlerType)?"
        }.joined(separator: "\n")

        let mockFns = methods.map { fn in
            let params = fn.signature.parameterClause.parameters.map { $0.firstName.text }.joined(separator: ", ")
            let signature = fn.signature.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasReturn = fn.signature.returnClause != nil && fn.signature.returnClause?.type.trimmedDescription != "Void"
            let returnPrefix = hasReturn ? "return " : ""
            let isAsync = fn.signature.effectSpecifiers?.asyncSpecifier != nil
            let isThrowing = fn.signature.effectSpecifiers?.throwsClause?.throwsSpecifier != nil
            let callPrefix: String
            if isAsync {
                callPrefix = "try await "
            } else if isThrowing {
                callPrefix = "try "
            } else {
                callPrefix = ""
            }
            return "    func \(fn.name.text)\(signature) {\n        if let handler = \(fn.name.text)Handler { \(returnPrefix)\(callPrefix)handler(\(params)) }\n        fatalError(\"Not implemented in mock\")\n    }"
        }.joined(separator: "\n\n")

        let protocolDecl = """

\(access)protocol \(protocolName) {
\(protocolFns)
}
"""

        let mockDecl = """

\(access)final class \(mockName): \(protocolName) {
\(mockProps)

    \(access)init() {}

\(mockFns)
}
"""

        return [DeclSyntax(stringLiteral: protocolDecl), DeclSyntax(stringLiteral: mockDecl)]
    }

    private static func diagnostic(for node: some SyntaxProtocol, kind: RepositoryDiagnostic) -> Diagnostic {
        Diagnostic(node: Syntax(node), message: kind)
    }
}

private extension FunctionDeclSyntax {
    var handlerType: String {
        let params = signature.parameterClause.parameters.map { $0.type.trimmedDescription }.joined(separator: ", ")
        let asyncPart = signature.effectSpecifiers?.asyncSpecifier != nil ? " async" : ""
        let throwsPart = signature.effectSpecifiers?.throwsClause?.throwsSpecifier != nil ? " throws" : ""
        let returnType = signature.returnClause?.type.trimmedDescription ?? "Void"
        return "(\(params))\(asyncPart)\(throwsPart) -> \(returnType)"
    }
}

private extension TypeSyntax {
    var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
}
