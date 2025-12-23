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
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .mustBeStruct)])
        }

        guard let config = extractConfig(from: node) else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .missingType)])
        }

        let holderName = "__ArcheryVMHolder"
        let viewName = structDecl.name.text
        let isPublic = structDecl.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
        let access = isPublic ? "public " : ""

        // Use @State with @Observable holder
        let storage = """
@SwiftUI.Environment(\\.archeryContainer) private var __archeryEnv
@SwiftUI.State private var vmHolder = \(holderName)(factory: { \(config.typeName)() })
"""

        let computed = """
var vm: \(config.typeName) { vmHolder.value(container: __archeryEnv) }
"""

        let loadWrapper = """
@SwiftUI.ViewBuilder var bodyWithVMLoad: some SwiftUI.View {
    body.task {
        let anyVM: Any = vm
        if let loadable = anyVM as? ArcheryLoadable {
            await loadable.load()
        }
    }
}
"""

        let previewContainer = """
\(access)static func previewContainer(seed: ((inout EnvContainer) -> Void)? = nil) -> EnvContainer {
    var c = EnvContainer()
    c.registerFactory { \(config.typeName)() }
    seed?(&c)
    return c
}
"""

        // Use @Observable for the holder class - fileprivate allows @Observable synthesis to work
        let holder = """
@MainActor @Observable fileprivate final class \(holderName) {
    fileprivate var cached: \(config.typeName)?
    fileprivate let factory: @MainActor () -> \(config.typeName)
    init(factory: @escaping @MainActor () -> \(config.typeName) = { \(config.typeName)() }) {
        self.factory = factory
    }
    func value(container: EnvContainer?) -> \(config.typeName) {
        if let cached { return cached }
        if let container {
            if let resolved: \(config.typeName) = container.resolve() {
                self.cached = resolved
                return resolved
            }
            fatalError("Archery: EnvContainer missing registration for \(config.typeName). Register it in EnvContainer or supply a factory.")
        }
        let created = factory()
        self.cached = created
        return created
    }
}
"""

        let hasCustomPreviewContainer = structDecl.memberBlock.members.contains { member in
            guard let fn = member.decl.as(FunctionDeclSyntax.self) else { return false }
            return fn.name.text == "makePreviewContainer"
        }
        let previewContainerCall = hasCustomPreviewContainer
            ? "\(viewName).makePreviewContainer()"
            : "\(viewName).previewContainer()"

        let previews = """
#if DEBUG
\(access)struct \(viewName)_Previews: SwiftUI.PreviewProvider {
    \(access)static var previews: some SwiftUI.View {
        let container = \(previewContainerCall)
        return \(viewName)()
            .environment(\\.archeryContainer, container)\(previewTask(config))
    }
}
#endif
"""

        let modifier = """
#if DEBUG
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
struct \(viewName)PreviewModifier: SwiftUI.PreviewModifier {
    /// Use with `#Preview(traits: .modifier(\(viewName)PreviewModifier())) { \(viewName)() }`
    /// Optionally pass a seeding closure to register mocks: `.modifier(\(viewName)PreviewModifier { c in /* c.register(mock) */ })`
    typealias Body = SwiftUI.AnyView
    typealias Context = Void
    let seed: ((inout EnvContainer) -> Void)?
    init(seed: ((inout EnvContainer) -> Void)? = nil) { self.seed = seed }
    func body(content: Content, context: Context) -> Body {
        let container = \(hasCustomPreviewContainer ? "\(viewName).makePreviewContainer()" : "\(viewName).previewContainer(seed: seed)")
        return SwiftUI.AnyView(content.environment(\\.archeryContainer, container))
    }
}
#endif
"""

        var decls: [DeclSyntax] = [
            DeclSyntax(stringLiteral: storage),
            DeclSyntax(stringLiteral: computed)
        ]

        if config.autoLoad {
            decls.append(DeclSyntax(stringLiteral: loadWrapper))
        }

        decls.append(contentsOf: [
            DeclSyntax(stringLiteral: previewContainer),
            DeclSyntax(stringLiteral: modifier),
            DeclSyntax(stringLiteral: holder),
            DeclSyntax(stringLiteral: previews)
        ])

        return decls
    }

    private static func extractConfig(from node: AttributeSyntax) -> ViewModelConfig? {
        var typeName: String?
        var autoLoad = true

        if let generic = node.attributeName.as(IdentifierTypeSyntax.self)?.genericArgumentClause?.arguments.first?.argument {
            typeName = cleanedTypeName(generic.trimmedDescription)
        }

        if let args = node.arguments?.as(LabeledExprListSyntax.self) {
            for (index, arg) in args.enumerated() {
                let label = arg.label?.text

                if label == nil && typeName == nil && index == 0 {
                    typeName = cleanedTypeName(arg.expression.trimmedDescription)
                    continue
                }

                if label == "type", typeName == nil {
                    typeName = cleanedTypeName(arg.expression.trimmedDescription)
                    continue
                }

                if label == "autoLoad" {
                    autoLoad = parseBool(arg.expression) ?? true
                    continue
                }
            }
        }

        guard let typeName else { return nil }

        return .init(typeName: typeName, autoLoad: autoLoad)
    }

    private static func diagnostic(for node: some SyntaxProtocol, kind: ViewModelBoundDiagnostic) -> Diagnostic {
        Diagnostic(node: Syntax(node), message: kind)
    }

    private static func previewTask(_ config: ViewModelConfig) -> String {
        guard config.autoLoad else { return "" }
        return "\n            .task {\n                if let vm: \(config.typeName) = container.resolve(),\n                   let loadable = (vm as Any) as? ArcheryLoadable {\n                    await loadable.load()\n                }\n            }"
    }

    private static func parseBool(_ expr: some ExprSyntaxProtocol) -> Bool? {
        guard let boolLiteral = expr.as(BooleanLiteralExprSyntax.self) else { return nil }
        return boolLiteral.literal.tokenKind == .keyword(.true)
    }

    private static func cleanedTypeName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".self", with: "")
    }
}

private struct ViewModelConfig {
    let typeName: String
    let autoLoad: Bool
}

private extension SyntaxProtocol {
    var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
}
