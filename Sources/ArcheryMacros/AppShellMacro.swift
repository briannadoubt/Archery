import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

enum AppShellDiagnostic: String, DiagnosticMessage {
    case mustBeStruct
    case missingTabsEnum

    var message: String {
        switch self {
        case .mustBeStruct: return "@AppShell can only be applied to a struct"
        case .missingTabsEnum: return "@AppShell requires a nested Tab enum conforming to CaseIterable"
        }
    }

    var diagnosticID: MessageID { .init(domain: "ArcheryMacros", id: rawValue) }
    var severity: DiagnosticSeverity { .error }
}

public enum AppShellMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .mustBeStruct)])
        }

        guard let tabEnum = structDecl.memberBlock.members.compactMap({ $0.decl.as(EnumDeclSyntax.self) }).first(where: { $0.name.text == "Tab" }) else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .missingTabsEnum)])
        }

        let tabCases: [String] = tabEnum.memberBlock.members.compactMap { member in
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self), let element = caseDecl.elements.first else { return nil }
            return element.name.text
        }
        guard let firstCase = tabCases.first else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .missingTabsEnum)])
        }

        let sheetEnum = structDecl.memberBlock.members.compactMap { $0.decl.as(EnumDeclSyntax.self) }.first(where: { $0.name.text == "Sheet" })
        let fullEnum = structDecl.memberBlock.members.compactMap { $0.decl.as(EnumDeclSyntax.self) }.first(where: { $0.name.text == "FullScreen" })

        let sheetCases: [(String, [String])] = sheetEnum.map { enumDecl in
            enumDecl.memberBlock.members.compactMap { member in
                guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self), let element = caseDecl.elements.first else { return nil }
                let params = element.parameterClause?.parameters.map { $0.firstName?.text ?? "_" } ?? []
                return (element.name.text, params)
            }
        } ?? []

        let fullCases: [(String, [String])] = fullEnum.map { enumDecl in
            enumDecl.memberBlock.members.compactMap { member in
                guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self), let element = caseDecl.elements.first else { return nil }
                let params = element.parameterClause?.parameters.map { $0.firstName?.text ?? "_" } ?? []
                return (element.name.text, params)
            }
        } ?? []

        let isPublic = structDecl.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
        let access = isPublic ? "public " : ""

        let routeEnums = tabCases.map { name in
            "    enum \(name.capitalizedRouteName): Hashable { case root }"
        }.joined(separator: "\n")

        let tabItems = tabCases.map { name -> String in
            let route = name.capitalizedRouteName
            let sheetLine = sheetEnum != nil ? ".sheet(item: sheetBinding(), content: buildSheet)" : ""
            let fullLine = fullEnum != nil ? ".fullScreenCover(item: fullScreenBinding(), content: buildFullScreen)" : ""
            return """
            SwiftUI.NavigationStack(path: binding(for: .\(name), as: \(route).self)) {
                SwiftUI.Text(\"\(name)\")
            }
            .navigationDestination(for: \(route).self) { _ in
                SwiftUI.Text(\"\(name) destination\")
            }
            \(sheetLine)
            \(fullLine)
            .tabItem {
                SwiftUI.Label(\"\(name)\", systemImage: \"circle\")
            }
            .tag(Tab.\(name))
            """
        }.joined(separator: "\n")

        let sheetState = sheetEnum != nil ? "    @SwiftUI.State private var activeSheet: Sheet?\n" : ""
        let fullState = fullEnum != nil ? "    @SwiftUI.State private var activeFullScreen: FullScreen?\n" : ""

        func makeSheetCases() -> String {
            sheetCases.map { name, params in
                let bindings = params.enumerated().map { "let p\($0.offset)" }.joined(separator: ", ")
                let payload = params.enumerated().map { "p\($0.offset)" }.joined(separator: ", ")
                let pattern = params.isEmpty ? "case .\(name):" : "case .\(name)(\(bindings)):"
                let payloadArgs = params.isEmpty ? "" : ", payload: (\(payload))"
                return "\(pattern) return Self.sheetView(\\\"\(name)\\\")\(payloadArgs) { activeSheet = nil }"
            }.joined(separator: "\n        ")
        }

        func makeFullCases() -> String {
            fullCases.map { name, params in
                let bindings = params.enumerated().map { "let p\($0.offset)" }.joined(separator: ", ")
                let payload = params.enumerated().map { "p\($0.offset)" }.joined(separator: ", ")
                let pattern = params.isEmpty ? "case .\(name):" : "case .\(name)(\(bindings)):"
                let payloadArgs = params.isEmpty ? "" : ", payload: (\(payload))"
                return "\(pattern) return Self.fullScreenView(\\\"\(name)\\\")\(payloadArgs) { activeFullScreen = nil }"
            }.joined(separator: "\n        ")
        }

        let sheetHelpers: String = sheetEnum != nil ? """
    private func sheetBinding() -> SwiftUI.Binding<Sheet?> {
        SwiftUI.Binding(get: { activeSheet }, set: { activeSheet = $0 })
    }

    private func buildSheet(_ sheet: Sheet) -> some SwiftUI.View {
        switch sheet {
        \(makeSheetCases())
        }
    }
""" : ""

        let fullHelpers: String = fullEnum != nil ? """
    private func fullScreenBinding() -> SwiftUI.Binding<FullScreen?> {
        SwiftUI.Binding(get: { activeFullScreen }, set: { activeFullScreen = $0 })
    }

    private func buildFullScreen(_ cover: FullScreen) -> some SwiftUI.View {
        switch cover {
        \(makeFullCases())
        }
    }
""" : ""

        let shellView = """
\(access)struct ShellView: SwiftUI.View {
    @SwiftUI.State private var selection: Tab = .\(firstCase)
    @SwiftUI.State private var paths: [Tab: [AnyHashable]] = [:]
\(sheetState)\(fullState)    private var container: EnvContainer

\(routeEnums)

    \(access)init(container: EnvContainer = EnvContainer(), patch: ((inout EnvContainer) -> Void)? = nil) {
        var c = container
        patch?(&c)
        Self.register(into: &c)
        self.container = c
        Tab.allCases.forEach { paths[$0] = [] }
    }

    \(access)var body: some SwiftUI.View {
        SwiftUI.TabView(selection: $selection) {
\(tabItems)
        }
        .environment(\\.archeryContainer, container)
    }

    private func binding<Route: Hashable>(for tab: Tab, as _: Route.Type) -> SwiftUI.Binding<[Route]> {
        SwiftUI.Binding(
            get: {
                (paths[tab] as? [Route]) ?? []
            },
            set: { newValue in
                paths[tab] = newValue.map { $0 as AnyHashable }
            }
        )
    }
\(sheetHelpers)\(fullHelpers)    \(access)static func register(into container: inout EnvContainer) {
        container.registerFactory { Self.init() }
        container.register(Tab.allCases)
        \(sheetEnum != nil ? "container.registerFactory { Sheet?.none }; container.registerFactory { Sheet.self }" : "")
        \(fullEnum != nil ? "container.registerFactory { FullScreen?.none }; container.registerFactory { FullScreen.self }" : "")
    }
}
"""

        let previews = """
#if DEBUG
\(access)struct ShellView_Previews: SwiftUI.PreviewProvider {
    \(access)static var previews: some SwiftUI.View { ShellView() }
}
#endif
"""

        var members: [DeclSyntax] = [DeclSyntax(stringLiteral: shellView), DeclSyntax(stringLiteral: previews)]

        if sheetEnum != nil {
            members.append(DeclSyntax(stringLiteral: "extension Sheet: Identifiable { public var id: String { String(describing: self) } }"))
        }
        if fullEnum != nil {
            members.append(DeclSyntax(stringLiteral: "extension FullScreen: Identifiable { public var id: String { String(describing: self) } }"))
        }

        return members
    }

    private static func diagnostic(for node: some SyntaxProtocol, kind: AppShellDiagnostic) -> Diagnostic {
        Diagnostic(node: Syntax(node), message: kind)
    }
}

private extension String {
    var capitalizedRouteName: String {
        guard let first = first else { return "Route" }
        return first.uppercased() + dropFirst() + "Route"
    }
}
