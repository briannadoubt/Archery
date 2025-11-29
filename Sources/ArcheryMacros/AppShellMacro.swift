import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

enum AppShellDiagnostic: String, DiagnosticMessage {
    case mustBeStruct
    case missingTabsEnum
    case invalidWindowScene

    var message: String {
        switch self {
        case .mustBeStruct: return "@AppShell can only be applied to a struct"
        case .missingTabsEnum: return "@AppShell requires a nested Tab enum conforming to CaseIterable"
        case .invalidWindowScene: return "Window scene builders must return some Scene"
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

        let hasDIManual = structDecl.attributes.contains { attr in
            attr.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "DIManual"
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
        let windowEnum = structDecl.memberBlock.members.compactMap { $0.decl.as(EnumDeclSyntax.self) }.first(where: { $0.name.text == "Window" })

        let customRouteEnums: [String: String] = structDecl.memberBlock.members.compactMap { $0.decl.as(EnumDeclSyntax.self) }.reduce(into: [:]) { acc, enumDecl in
            let name = enumDecl.name.text
            if tabCases.contains(where: { $0.capitalizedRouteName == name }) {
                acc[name] = name
            }
        }

        let hasRegisterDeps = structDecl.memberBlock.members.contains { member in
            guard let fn = member.decl.as(FunctionDeclSyntax.self) else { return false }
            return fn.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) && fn.name.text == "registerDependencies"
        }

        let hasPreviewSeed = structDecl.memberBlock.members.contains { member in
            guard let fn = member.decl.as(FunctionDeclSyntax.self) else { return false }
            return fn.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) && fn.name.text == "previewSeed"
        }

        let sheetBuilderName = structDecl.memberBlock.members.compactMap { member -> String? in
            guard let fn = member.decl.as(FunctionDeclSyntax.self) else { return nil }
            guard fn.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) else { return nil }
            let hasAttr = fn.attributes.contains { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "ShellSheet" }
            if hasAttr || fn.name.text == "buildSheet" { return fn.name.text }
            return nil
        }.first

        let fullBuilderName = structDecl.memberBlock.members.compactMap { member -> String? in
            guard let fn = member.decl.as(FunctionDeclSyntax.self) else { return nil }
            guard fn.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) else { return nil }
            let hasAttr = fn.attributes.contains { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "ShellFullScreen" }
            if hasAttr || fn.name.text == "buildFullScreen" { return fn.name.text }
            return nil
        }.first

        let windowBuilderName = structDecl.memberBlock.members.compactMap { member -> String? in
            guard let fn = member.decl.as(FunctionDeclSyntax.self) else { return nil }
            guard fn.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) else { return nil }
            let hasAttr = fn.attributes.contains { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "ShellWindow" }
            if hasAttr || fn.name.text == "buildWindow" { return fn.name.text }
            return nil
        }.first

        let tabBuilders: [String: String] = structDecl.memberBlock.members.compactMap { member -> (String, String)? in
            guard let fn = member.decl.as(FunctionDeclSyntax.self) else { return nil }
            guard fn.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) else { return nil }
            guard let firstParam = fn.signature.parameterClause.parameters.first else { return nil }
            let typeName = firstParam.type.trimmedDescription
            guard tabCases.contains(where: { $0.capitalizedRouteName == typeName }) else { return nil }
            return (typeName, fn.name.text)
        }.reduce(into: [:]) { acc, pair in acc[pair.0] = pair.1 }

        let autoRegisterTypes: [String] = structDecl.memberBlock.members.compactMap { member in
            if let s = member.decl.as(StructDeclSyntax.self), s.attributes.contains(where: { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "AutoRegister" }) {
                return s.name.text
            }
            if let c = member.decl.as(ClassDeclSyntax.self), c.attributes.contains(where: { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "AutoRegister" }) {
                return c.name.text
            }
            if let a = member.decl.as(ActorDeclSyntax.self), a.attributes.contains(where: { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "AutoRegister" }) {
                return a.name.text
            }
            return nil
        }

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
            if let custom = customRouteEnums[name.capitalizedRouteName] {
                return "    typealias \(name.capitalizedRouteName) = \(custom)"
            }
            return "    enum \(name.capitalizedRouteName): Hashable { case root }"
        }.joined(separator: "\n")

        let tabItems = tabCases.map { name -> String in
            let route = name.capitalizedRouteName
            let sheetLine = sheetEnum != nil ? ".sheet(item: sheetBinding(), content: buildSheet)" : ""
            let fullLine = fullEnum != nil ? ".fullScreenCover(item: fullScreenBinding(), content: buildFullScreen)" : ""
            let contentBuilder = tabBuilders[route] ?? "defaultTabContent"
            let destinationBuilder = tabBuilders[route] ?? "defaultDestination"
            return """
            SwiftUI.NavigationStack(path: binding(for: .\(name), as: \(route).self)) {
                Self.\(contentBuilder)(.root, container)
            }
            .navigationDestination(for: \(route).self) { route in
                Self.\(destinationBuilder)(route, container)
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
                if let builder = sheetBuilderName {
                    let callPayload = params.isEmpty ? "sheet" : "Sheet.\(name)(\(payload))"
                    return "\(pattern) return Self.\(builder)(\(callPayload), container)"
                }
                return "\(pattern) return Self.sheetView(\\\"\(name)\\\")\(payloadArgs) { activeSheet = nil }"
            }.joined(separator: "\n        ")
        }

        func makeFullCases() -> String {
            fullCases.map { name, params in
                let bindings = params.enumerated().map { "let p\($0.offset)" }.joined(separator: ", ")
                let payload = params.enumerated().map { "p\($0.offset)" }.joined(separator: ", ")
                let pattern = params.isEmpty ? "case .\(name):" : "case .\(name)(\(bindings)):" 
                let payloadArgs = params.isEmpty ? "" : ", payload: (\(payload))"
                if let builder = fullBuilderName {
                    let callPayload = params.isEmpty ? "cover" : "FullScreen.\(name)(\(payload))"
                    return "\(pattern) return Self.\(builder)(\(callPayload), container)"
                }
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

        let registerWorking = hasDIManual ? "" : "Self.register(into: &working)"
        let registerPreview = hasDIManual ? "" : "Self.register(into: &c)"

        let shellView = """
\(access)struct ShellView: SwiftUI.View {
    @SwiftUI.State private var selection: Tab
    @SwiftUI.State private var paths: [Tab: [AnyHashable]]
\(sheetState)\(fullState)    private var container: EnvContainer

\(routeEnums)

    // Default builders; override with static funcs matching route types
    private static func defaultTabContent<Route>(_ route: Route, _ container: EnvContainer) -> some SwiftUI.View {
        SwiftUI.Text(String(describing: route))
    }

    private static func defaultDestination<Route>(_ route: Route, _ container: EnvContainer) -> some SwiftUI.View {
        SwiftUI.Text(String(describing: route))
    }

    \(access)init(
        selection: Tab = .\(firstCase),
        base: EnvContainer = EnvContainer(),
        mergeFrom parent: EnvContainer? = nil,
        patch: ((inout EnvContainer) -> Void)? = nil
    ) {
        self._selection = SwiftUI.State(initialValue: selection)
        let initialPaths = Dictionary(uniqueKeysWithValues: Tab.allCases.map { ($0, [AnyHashable]()) })
        self._paths = SwiftUI.State(initialValue: initialPaths)

        let working = EnvContainer()
        base.merge(into: working)
        parent?.merge(into: working)
        \(registerWorking)
        \(hasRegisterDeps ? "Self.registerDependencies(into: &working)" : "")
        patch?(&working)
        self.container = working
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
        \(!autoRegisterTypes.isEmpty ? "Self.__autoRegister(into: &container)" : "")
    }

    \(access)static func previewContainer(seed: ((inout EnvContainer) -> Void)? = nil, mergeFrom parent: EnvContainer? = nil) -> EnvContainer {
        let c = EnvContainer()
        parent?.merge(into: c)
        \(registerPreview)
        \(hasRegisterDeps ? "Self.registerDependencies(into: &c)" : "")
        \(hasPreviewSeed ? "Self.previewSeed(&c)" : "")
        seed?(&c)
        return c
    }
}
"""

        let previews = """
#if DEBUG
\(access)struct ShellView_Previews: SwiftUI.PreviewProvider {
    \(access)static var previews: some SwiftUI.View {
        let container = ShellView.previewContainer()
        return SwiftUI.Group {
            ForEach(Array(Tab.allCases), id: \\.self) { tab in
                ShellView(selection: tab, mergeFrom: container)
                    .environment(\\.archeryContainer, container)
                    .previewDisplayName(String(describing: tab))
            }
        }
    }
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
        if let windowEnum {
            let windowBuilderCall = windowBuilderName ?? ""
            members.append(DeclSyntax(stringLiteral: "extension Window: Identifiable { public var id: String { String(describing: self) } }"))

            let windowScenes = """
#if os(macOS) || os(iOS)
\(access)struct ShellScenes: SwiftUI.Scene {
    private let container: EnvContainer
    private let windowBuilder: ((Window, EnvContainer) -> any SwiftUI.Scene)?

    init(container: EnvContainer = EnvContainer(), mergeFrom parent: EnvContainer? = nil, builder: ((Window, EnvContainer) -> any SwiftUI.Scene)? = nil) {
        let working = EnvContainer()
        parent?.merge(into: working)
        container.merge(into: working)
        self.container = working
        self.windowBuilder = builder
    }

    var body: some SwiftUI.Scene {
        SwiftUI.SceneBuilder.buildBlock(
            \(windowEnum.memberBlock.members.compactMap { member in
                guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self), let element = caseDecl.elements.first else { return nil }
                let name = element.name.text
                if !windowBuilderCall.isEmpty {
                    return "Self.makeScene { Self.\(windowBuilderCall)(.\(name), container) }"
                }
                return "SwiftUI.WindowGroup(\"\(name)\") { ShellView(mergeFrom: container) }"
            }.joined(separator: ",\n            "))
    }

    private static func makeScene(_ builder: @escaping () -> any SwiftUI.Scene) -> some SwiftUI.Scene {
        builder()
    }
}
#endif
"""
            members.append(DeclSyntax(stringLiteral: windowScenes))
        }

        if !autoRegisterTypes.isEmpty {
            let autoLines = autoRegisterTypes.map { "container.registerFactory { \($0)() }" }.joined(separator: "\n        ")
            members.append(DeclSyntax(stringLiteral: "extension ShellView { static func __autoRegister(into container: inout EnvContainer) {\n        \(autoLines)\n    } }"))
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

private extension SyntaxProtocol {
    var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
}
