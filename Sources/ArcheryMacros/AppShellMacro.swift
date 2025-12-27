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
    // MARK: - Configuration Parsing

    struct Config {
        var schemaTypes: [String] = []  // e.g., ["TaskItem", "Project"]
    }

    static func parseConfig(from node: AttributeSyntax) -> Config {
        var config = Config()

        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return config
        }

        for argument in arguments {
            let label = argument.label?.text

            if label == "schema" {
                // Parse array literal: [Cat.self, Dog.self, ...]
                if let arrayExpr = argument.expression.as(ArrayExprSyntax.self) {
                    for element in arrayExpr.elements {
                        // Each element is Type.self - extract the type name
                        let expr = element.expression.trimmedDescription
                        if expr.hasSuffix(".self") {
                            config.schemaTypes.append(String(expr.dropLast(5)))
                        }
                    }
                }
            }
        }

        return config
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .mustBeStruct)])
        }

        let structName = structDecl.name.text
        let config = parseConfig(from: node)

        guard let tabEnum = structDecl.memberBlock.members.compactMap({ $0.decl.as(EnumDeclSyntax.self) }).first(where: { $0.name.text == "Tab" }) else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .missingTabsEnum)])
        }

        let hasDIManual = structDecl.attributes.contains { attr in
            attr.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "DIManual"
        }

        let tabCaseInfos: [TabCaseInfo] = tabEnum.memberBlock.members.compactMap { member in
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self), let element = caseDecl.elements.first else { return nil }
            let name = element.name.text
            let requirement = extractTabEntitlement(from: caseDecl)
            return TabCaseInfo(name: name, entitlement: requirement)
        }
        let tabCases: [String] = tabCaseInfos.map(\.name)
        guard let firstCase = tabCases.first else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .missingTabsEnum)])
        }

        // Check if any tabs have entitlement requirements
        let hasTabEntitlements = tabCaseInfos.contains { $0.entitlement != nil }

        // Note: Sheet/FullScreen enums are no longer used - coordinator handles presentations
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

        // Check for static analyticsProviders property
        let hasAnalyticsProviders = structDecl.memberBlock.members.contains { member in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { return false }
            let isStatic = varDecl.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
            let hasName = varDecl.bindings.contains { $0.pattern.trimmedDescription == "analyticsProviders" }
            return isStatic && hasName
        }

        // Only generate database when schema is provided (explicit opt-in)
        let useGeneratedDatabase = !config.schemaTypes.isEmpty

        // Check for static themeManager property
        let hasThemeManager = structDecl.memberBlock.members.contains { member in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { return false }
            let isStatic = varDecl.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
            let hasName = varDecl.bindings.contains { $0.pattern.trimmedDescription == "themeManager" }
            return isStatic && hasName
        }

        // Check if user already defined body (don't override)
        let hasBody = structDecl.memberBlock.members.contains { member in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { return false }
            return varDecl.bindings.contains { $0.pattern.trimmedDescription == "body" }
        }

        // Check if user already defined init (don't override)
        let hasInit = structDecl.memberBlock.members.contains { member in
            member.decl.is(InitializerDeclSyntax.self)
        }

        // Note: sheetBuilderName and fullBuilderName removed - coordinator handles presentations via route resolution

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
            // Match both "DashboardRoute" and "ShellView.DashboardRoute"
            let normalizedType = typeName.hasPrefix("ShellView.") ? String(typeName.dropFirst("ShellView.".count)) : typeName
            guard let matchedTab = tabCases.first(where: { $0.capitalizedRouteName == normalizedType }) else { return nil }
            return (matchedTab.capitalizedRouteName, fn.name.text)
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

        // Note: sheetCases and fullCases removed - coordinator handles presentations via route resolution

        let isPublic = structDecl.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
        let access = isPublic ? "public " : ""

        // For each tab, generate route types only when needed:
        // - Custom enum inside app struct -> generate typealias
        // - No builder -> generate simple enum
        // - Has builder -> external @Route type exists, don't generate anything (use external type directly)
        let routeEnums = tabCases.compactMap { name -> String? in
            let routeName = name.capitalizedRouteName
            if let custom = customRouteEnums[routeName] {
                // Custom enum defined inside the app struct
                return "    typealias \(routeName) = \(custom)"
            }
            if tabBuilders[routeName] != nil {
                // Has a builder, external @Route type exists at file scope
                // Don't generate anything - use the external type directly
                return nil
            }
            // No builder, generate simple enum without deep link support
            return "    enum \(routeName): NavigationRoute, Codable { case root }"
        }.joined(separator: "\n")

        // Note: Old tabItems, sheetState, fullState, sheetHelpers, fullHelpers removed
        // The new coordinator-driven shell handles all presentations via NavigationCoordinator

        let registerWorking = hasDIManual ? "" : "Self.register(into: &working)"
        let registerPreview = hasDIManual ? "" : "Self.register(into: &c)"

        // Generate __autoRegister method inline if needed
        let autoRegisterMethod: String
        if !autoRegisterTypes.isEmpty {
            let autoLines = autoRegisterTypes.map { "        container.registerFactory { \($0)() }" }.joined(separator: "\n")
            autoRegisterMethod = """

    private static func __autoRegister(into container: inout EnvContainer) {
\(autoLines)
    }
"""
        } else {
            autoRegisterMethod = ""
        }

        // Generate tab entitlement methods inline if needed
        let tabEntitlementMethods: String
        if hasTabEntitlements {
            let tabRequirementCases = tabCaseInfos.map { info in
                let requirement = info.entitlement?.generateRequirementExpr() ?? ".none"
                return "        case .\(info.name): return \(requirement)"
            }.joined(separator: "\n")

            let tabBehaviorCases = tabCaseInfos.map { info in
                let behavior = info.entitlement?.behavior ?? "hidden"
                return "        case .\(info.name): return .\(behavior)"
            }.joined(separator: "\n")

            let tabAutoPaywallCases = tabCaseInfos.map { info in
                let autoPaywall = info.entitlement?.autoPaywall ?? true
                return "        case .\(info.name): return \(autoPaywall)"
            }.joined(separator: "\n")

            tabEntitlementMethods = """

    /// Returns the entitlement requirement for a specific tab
    \(access)static func tabRequirement(for tab: Tab) -> Archery.EntitlementRequirement {
        switch tab {
\(tabRequirementCases)
        }
    }

    /// Returns the behavior for a gated tab when user lacks entitlement
    \(access)static func tabBehavior(for tab: Tab) -> Archery.GatedTabBehavior {
        switch tab {
\(tabBehaviorCases)
        }
    }

    /// Returns whether to auto-present paywall when tab is blocked
    \(access)static func shouldAutoPaywall(for tab: Tab) -> Bool {
        switch tab {
\(tabAutoPaywallCases)
        }
    }
"""
        } else {
            tabEntitlementMethods = ""
        }

        // Generate route resolution switch for each tab
        // When there's a builder, use external file-scope route type directly
        // Otherwise use ShellView-local enum type
        let routeResolutionCases = tabCases.map { name -> String in
            let route = name.capitalizedRouteName
            let hasBuilder = tabBuilders[route] != nil
            let routeType = hasBuilder ? route : "ShellView.\(route)"
            let builderCall: String
            if let builder = tabBuilders[route] {
                builderCall = "\(structName).\(builder)(route, container)"
            } else {
                builderCall = "SwiftUI.AnyView(SwiftUI.Text(String(describing: route)))"
            }
            return """
                        if let route = anyRoute.as(\(routeType).self) {
                            return SwiftUI.AnyView(\(builderCall))
                        }
            """
        }.joined(separator: "\n")

        // Generate tab root views
        let tabRootViews = tabCases.map { name -> String in
            let route = name.capitalizedRouteName
            let hasBuilder = tabBuilders[route] != nil
            let routeType = hasBuilder ? route : "ShellView.\(route)"
            if let builder = tabBuilders[route] {
                return "            case .\(name): return SwiftUI.AnyView(\(structName).\(builder)(\(routeType).root, container))"
            } else {
                return "            case .\(name): return SwiftUI.AnyView(SwiftUI.Text(\"\(name)\"))"
            }
        }.joined(separator: "\n")

        // Generate tab visibility checks for entitlement-gated tabs
        let tabVisibilityChecks = tabCaseInfos.filter { $0.entitlement != nil }.map { info -> String in
            let behavior = info.entitlement?.behavior ?? "hidden"
            if behavior == "hidden" {
                return "            if tab == .\(info.name) { return store.hasEntitlement(\(info.entitlement!.entitlements.map { ".\($0)" }.first ?? ".none")) }"
            }
            return ""
        }.filter { !$0.isEmpty }.joined(separator: "\n")

        // Generate tab locked checks
        let tabLockedChecks = tabCaseInfos.filter { $0.entitlement?.behavior == "locked" }.map { info -> String in
            let entitlement = info.entitlement!.entitlements.first ?? "none"
            return "            if tab == .\(info.name) { return !store.hasEntitlement(.\(entitlement)) }"
        }.joined(separator: "\n")

        // Generate entitlement checking for routes
        let routeEntitlementChecks = tabCaseInfos.compactMap { info -> String? in
            guard let ent = info.entitlement else { return nil }
            let route = info.name.capitalizedRouteName
            let requirement = ent.generateRequirementExpr()
            return "            if route is \(route) { return \(requirement) }"
        }.joined(separator: "\n")

        // Generate deep link tab matching
        // Note: We use the local route typealiases which point to external @Route-decorated types
        // that have fromURL static method
        let deepLinkTabMatching = tabCases.enumerated().map { (index, name) -> String in
            let route = name.capitalizedRouteName
            return """
                        case "\(name)":
                            var actions: [CoordinatorAction] = [.selectTab(index: \(index))]
                            if remaining.count > 0, let route = \(route).fromURL(path: remaining, query: query) {
                                actions.append(.push(AnyRoute(route)))
                            }
                            return .success(actions)
            """
        }.joined(separator: "\n")

        let shellView = """
// MARK: - Generated Navigation Coordinator

/// Generated NavigationCoordinator that powers the app shell.
///
/// Manages:
/// - Tab selection with entitlement gating
/// - Per-tab navigation stacks
/// - Sheet and fullscreen presentations (recursive)
/// - Flow management
/// - Deep link handling
@MainActor
\(access)final class ShellNavigationCoordinator: NavigationCoordinator<Tab> {
    private let container: EnvContainer
    private let _store: StoreKitManager

    \(access)init(container: EnvContainer = EnvContainer()) {
        self.container = container
        self._store = .shared
        super.init(initialTab: .\(firstCase))
        self.storeKitManager = _store
    }

    \(access)var store: StoreKitManager { _store }

    // MARK: - Route Resolution

    /// Resolve a type-erased route to its view
    \(access)func resolveView(for anyRoute: AnyRoute) -> SwiftUI.AnyView {
\(routeResolutionCases)
        return SwiftUI.AnyView(SwiftUI.Text("Unknown route: \\(anyRoute.id)"))
    }

    /// Get the root view for a tab
    \(access)func rootView(for tab: Tab) -> SwiftUI.AnyView {
        switch tab {
\(tabRootViews)
        }
    }

    // MARK: - Tab Visibility

    /// Returns visible tabs based on entitlements
    \(access)var visibleTabs: [Tab] {
        Tab.allCases.filter { tab in
\(tabVisibilityChecks.isEmpty ? "            return true" : tabVisibilityChecks + "\n            return true")
        }
    }

    /// Check if a tab is locked (visible but inaccessible)
    \(access)func isTabLocked(_ tab: Tab) -> Bool {
\(tabLockedChecks.isEmpty ? "        return false" : tabLockedChecks + "\n        return false")
    }

    // MARK: - Entitlement Checking

    override func checkEntitlement<R: NavigationRoute>(for route: R) -> EntitlementRequirement? {
\(routeEntitlementChecks.isEmpty ? "        return nil" : routeEntitlementChecks + "\n        return nil")
    }

    // MARK: - Deep Link Resolution

    override func resolveDeepLink(_ url: URL) -> DeepLinkResolution? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return .invalidFormat("Could not parse URL")
        }

        let pathComponents = components.path.split(separator: "/").map(String.init)
        guard let firstPath = pathComponents.first else { return .notFound }

        // Handle flow deep links
        if firstPath == "flow" {
            guard pathComponents.count >= 2 else { return .notFound }
            let flowId = pathComponents[1]
            let step = pathComponents.count >= 4 && pathComponents[2] == "step" ? pathComponents[3] : nil
            return .flow(id: flowId, step: step)
        }

        let remaining = Array(pathComponents.dropFirst())
        let query = Dictionary(uniqueKeysWithValues:
            (components.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let value = item.value else { return nil }
                return (item.name, value)
            }
        )

        switch firstPath {
\(deepLinkTabMatching)
        default:
            return .notFound
        }
    }
}

// MARK: - Generated Shell View

/// Generated shell view powered by NavigationCoordinator.
///
/// Features:
/// - TabView with per-tab NavigationStacks
/// - Entitlement-gated tabs (locked/hidden)
/// - Recursive sheet presentations
/// - Full-screen presentations
/// - Deep link handling via onOpenURL
\(access)struct ShellView: SwiftUI.View {
    @SwiftUI.State private var coordinator: ShellNavigationCoordinator
    private var container: EnvContainer

\(routeEnums)

    \(access)init(
        selection: Tab = .\(firstCase),
        base: EnvContainer = EnvContainer(),
        mergeFrom parent: EnvContainer? = nil,
        patch: ((inout EnvContainer) -> Void)? = nil,
        persistence: NavigationPersistence = .enabled(key: "archery.navigation.\(Self.self)")
    ) {
        var working = EnvContainer()
        base.merge(into: working)
        parent?.merge(into: working)
        \(registerWorking)
        \(hasRegisterDeps ? "Self.registerDependencies(into: &working)" : "")
        patch?(&working)
        self.container = working
        self._coordinator = SwiftUI.State(initialValue: ShellNavigationCoordinator(container: working))

        // Configure analytics providers and framework-level auto-tracking
        Self.__configureAnalytics()
    }

    private static func __configureAnalytics() {
        // Configure providers (uses analyticsProviders if defined, otherwise DebugAnalyticsProvider)
        \(hasAnalyticsProviders ? "let providers = \(structName).analyticsProviders" : "let providers: [any AnalyticsProvider] = [DebugAnalyticsProvider()]")
        #if DEBUG
        let debugMode = true
        #else
        let debugMode = false
        #endif
        AnalyticsManager.shared.configure(providers: providers, enabled: true, debugMode: debugMode)

        // Bridge ArcheryEvent to AnalyticsManager automatically
        if ArcheryAnalyticsConfiguration.shared.eventHandler == nil {
            ArcheryAnalyticsConfiguration.shared.eventHandler = { event in
                let name = event.name
                let properties = event.properties
                Task { @MainActor in
                    AnalyticsManager.shared.track(name, properties: properties)
                }
            }
        }
    }

    \(access)var body: some SwiftUI.View {
        SwiftUI.TabView(selection: $coordinator.selectedTab) {
            SwiftUI.ForEach(coordinator.visibleTabs, id: \\.self) { tab in
                tabContent(for: tab)
                    .tabItem {
                        tabLabel(for: tab)
                    }
                    .tag(tab)
            }
        }
        .sheet(item: coordinator.sheetBinding(depth: 0)) { route in
            sheetContent(route: route, depth: 1)
        }
        #if !os(macOS)
        .fullScreenCover(item: coordinator.fullScreenBinding) { route in
            fullScreenContent(route: route)
        }
        #endif
        .environment(\\.navigationHandle, coordinator.makeHandle(for: .tab(0)))
        .environment(\\.archeryContainer, container)
        .environment(coordinator)
        .onOpenURL { url in
            _ = coordinator.handle(url: url)
        }
    }

    // MARK: - Tab Content

    @SwiftUI.ViewBuilder
    private func tabContent(for tab: Tab) -> some SwiftUI.View {
        if coordinator.isTabLocked(tab) {
            lockedTabContent(tab)
        } else {
            SwiftUI.NavigationStack(path: pathBinding(for: tab)) {
                coordinator.rootView(for: tab)
                    .navigationDestination(for: AnyRoute.self) { route in
                        coordinator.resolveView(for: route)
                    }
            }
            .environment(\\.navigationHandle, coordinator.makeHandle(for: .tab(tabIndex(tab))))
        }
    }

    @SwiftUI.ViewBuilder
    private func tabLabel(for tab: Tab) -> some SwiftUI.View {
        switch tab {
\(tabCases.map { name in
            "        case .\(name): SwiftUI.Label(\"\(name)\", systemImage: \"circle\")"
        }.joined(separator: "\n"))
        }
    }

    @SwiftUI.ViewBuilder
    private func lockedTabContent(_ tab: Tab) -> some SwiftUI.View {
        SwiftUI.ContentUnavailableView {
            SwiftUI.Label(String(describing: tab), systemImage: "lock.fill")
        } description: {
            SwiftUI.Text("Upgrade to unlock this feature.")
        } actions: {
            SwiftUI.Button("View Plans") {
                // Present paywall
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Sheet Content (Recursive via limited depth)

    /// Build sheet content with recursive presentation support
    /// Uses explicit views at each depth level to satisfy type checker
    private func sheetContent(route: AnyRoute, depth: Int) -> SwiftUI.AnyView {
        let content = SwiftUI.NavigationStack {
            coordinator.resolveView(for: route)
                .toolbar {
                    SwiftUI.ToolbarItem(placement: .cancellationAction) {
                        SwiftUI.Button("Done") {
                            coordinator.dismiss(levels: 1)
                        }
                    }
                }
        }
        .presentationDetents(detentsForRoute(route))
        .environment(\\.navigationHandle, coordinator.makeHandle(for: .sheet(depth: depth)))

        // Limit recursive sheet depth to prevent infinite type recursion
        if depth < 5 {
            return SwiftUI.AnyView(
                content.sheet(item: coordinator.sheetBinding(depth: depth)) { nextRoute in
                    self.sheetContent(route: nextRoute, depth: depth + 1)
                }
            )
        } else {
            return SwiftUI.AnyView(content)
        }
    }

    private func detentsForRoute(_ route: AnyRoute) -> Set<SwiftUI.PresentationDetent> {
        if case .sheet(let detents) = route.presentationStyle {
            return Set(detents.map(\\.presentationDetent))
        }
        return [.large]
    }

    // MARK: - Full Screen Content

    private func fullScreenContent(route: AnyRoute) -> SwiftUI.AnyView {
        let content = SwiftUI.NavigationStack {
            coordinator.resolveView(for: route)
                .toolbar {
                    SwiftUI.ToolbarItem(placement: .cancellationAction) {
                        SwiftUI.Button("Close") {
                            coordinator.fullScreenRoute = nil
                        }
                    }
                }
        }
        .sheet(item: coordinator.sheetBinding(depth: 0)) { sheetRoute in
            self.sheetContent(route: sheetRoute, depth: 1)
        }
        .environment(\\.navigationHandle, coordinator.makeHandle(for: .fullScreen()))

        return SwiftUI.AnyView(content)
    }

    // MARK: - Helpers

    private func pathBinding(for tab: Tab) -> SwiftUI.Binding<[AnyRoute]> {
        SwiftUI.Binding(
            get: { (coordinator.tabPaths[tab] as? [AnyRoute]) ?? [] },
            set: { coordinator.tabPaths[tab] = $0.map { $0 as AnyHashable } }
        )
    }

    private func tabIndex(_ tab: Tab) -> Int {
        Tab.allCases.firstIndex(of: tab).map { Tab.allCases.distance(from: Tab.allCases.startIndex, to: $0) } ?? 0
    }

    // MARK: - Static Registration

    \(access)static func register(into container: inout EnvContainer) {
        container.registerFactory { Self.init() }
        container.register(Tab.allCases)
        \(!autoRegisterTypes.isEmpty ? "Self.__autoRegister(into: &container)" : "")
    }

    \(access)static func previewContainer(seed: ((inout EnvContainer) -> Void)? = nil, mergeFrom parent: EnvContainer? = nil) -> EnvContainer {
        var c = EnvContainer()
        parent?.merge(into: c)
        \(registerPreview)
        \(hasRegisterDeps ? "Self.registerDependencies(into: &c)" : "")
        \(hasPreviewSeed ? "Self.previewSeed(&c)" : "")
        seed?(&c)
        return c
    }
\(autoRegisterMethod)\(tabEntitlementMethods)
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

        // Note: NavigationCoordinator subclass generation is available but not included here
        // due to Swift macro limitations around generating extensions at file scope.
        // Use the NavigationCoordinator base class directly for navigation coordination.

        // MARK: - Generated App Infrastructure

        // Generate state properties
        let stateObjects: String
        var objects: [String] = []
        if useGeneratedDatabase {
            // Use @State with @Observable GeneratedAppDatabase
            objects.append("    @SwiftUI.State private var __database = GeneratedAppDatabase.shared")
        }
        if hasThemeManager {
            objects.append("    @SwiftUI.State private var __themeManager = \(structName).themeManager")
        }
        objects.append("    @SwiftUI.State private var __store = StoreKitManager.shared")
        stateObjects = objects.joined(separator: "\n")

        // Generate init if not defined by user
        let generatedInit: String
        if !hasInit {
            generatedInit = """

    \(access)init() {
        Self.__configureAppearance()
    }

    private static func __configureAppearance() {
        #if os(iOS)
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]
        #endif
    }
"""
        } else {
            generatedInit = ""
        }

        // Generate body if not defined by user
        let generatedBody: String
        if !hasBody {
            let shellContent: String
            if useGeneratedDatabase {
                // Database loading/error handling
                shellContent = """
            SwiftUI.Group {
                if __database.isReady, let container = __database.container {
                    ShellView()
                        .databaseContainer(container)
                } else if let error = __database.error {
                    SwiftUI.ContentUnavailableView {
                        SwiftUI.Label("Database Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        SwiftUI.Text(error.localizedDescription)
                    } actions: {
                        SwiftUI.Button("Retry") {
                            _Concurrency.Task { await __database.setup() }
                        }
                    }
                } else {
                    SwiftUI.ProgressView("Loading...")
                        .task {
                            await __database.setup()
                        }
                }
            }
"""
            } else {
                shellContent = "            ShellView()"
            }

            let environmentObjects: String
            if hasThemeManager {
                environmentObjects = """

            .environment(__themeManager)
            .environment(__store)
            .preferredColorScheme(__themeManager.currentTheme.colorScheme)
"""
            } else {
                environmentObjects = """

            .environment(__store)
"""
            }

            generatedBody = """

    \(access)var body: some SwiftUI.Scene {
        SwiftUI.WindowGroup {
\(shellContent)\(environmentObjects)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        #endif
    }
"""
        } else {
            generatedBody = ""
        }

        // Check for static seedDemoData function
        let hasSeedDemoData = structDecl.memberBlock.members.contains { member in
            guard let fn = member.decl.as(FunctionDeclSyntax.self) else { return false }
            let isStatic = fn.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
            return isStatic && fn.name.text == "seedDemoData"
        }

        // Generate the database class if using new pattern
        let generatedDatabaseClass: String
        if useGeneratedDatabase {
            // Generate registration calls for each schema type
            let schemaRegistrations = config.schemaTypes.map { type in
                "            MigrationRegistry.shared.register(\(type).self)"
            }.joined(separator: "\n")

            // Generate query source registrations for schema types
            // Types in schema array must conform to HasQuerySources
            let querySourceCalls = config.schemaTypes.map { type in
                "            QuerySourceRegistry.shared.register(\(type).Sources())"
            }.joined(separator: "\n")

            // Generate clearAllData delete calls for each schema type
            let clearAllDataCalls = config.schemaTypes.map { type in
                "                try \(type).deleteAll(db)"
            }.joined(separator: "\n")

            // Generate seeding hook call if seedDemoData exists
            let seedingCall = hasSeedDemoData ? """

            // Seed demo data if provided
            try await \(structName).seedDemoData(container: container!)
""" : ""

            let previewSeedingCall = hasSeedDemoData ? """

                // Seed demo data
                try await \(structName).seedDemoData(container: db.container!)
""" : ""

            generatedDatabaseClass = """

// MARK: - Generated App Database

/// Auto-generated database container using @Observable pattern.
/// Schema: \(config.schemaTypes.joined(separator: ", "))
@MainActor
@Observable
\(access)final class GeneratedAppDatabase: AppDatabaseProtocol {
    \(access)static let shared = GeneratedAppDatabase()

    \(access)private(set) var container: PersistenceContainer?
    \(access)var isReady = false
    \(access)var error: Error?

    private init() {}

    \(access)func setup() async {
        guard container == nil else { return }

        do {
            // Register schema types with MigrationRegistry
\(schemaRegistrations)

            container = try PersistenceContainer.file(at: Self.defaultURL)
            PersistenceContainer.current = container

            // Run migrations for registered types
            let migrations = MigrationRegistry.shared.allMigrations()
            let runner = MigrationRunner(migrations)
            try runner.run(on: container!)\(seedingCall)

            // Register query sources for schema types
\(querySourceCalls)

            isReady = true
        } catch {
            self.error = error
        }
    }

    /// Clear all data from the database
    \(access)func clearAllData() async throws {
        guard let container else { return }
        try await container.write { db in
\(clearAllDataCalls)
        }
    }

    \(access)static func preview() -> GeneratedAppDatabase {
        let db = GeneratedAppDatabase()
        Task { @MainActor in
            do {
                // Register schema types
\(schemaRegistrations)

                db.container = try PersistenceContainer.inMemory()
                PersistenceContainer.current = db.container
                let migrations = MigrationRegistry.shared.allMigrations()
                let runner = MigrationRunner(migrations)
                try runner.run(on: db.container!)\(previewSeedingCall)

                // Register query sources
\(querySourceCalls)

                db.isReady = true
            } catch {
                db.error = error
            }
        }
        return db
    }

    private static var defaultURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleId = Bundle.main.bundleIdentifier ?? "com.archery.app"
        let appDir = appSupport.appendingPathComponent(bundleId)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("database.sqlite")
    }
}
"""
        } else {
            generatedDatabaseClass = ""
        }

        // Note: AppShortcutsProvider is generated by PeerMacro (at file scope)

        // Combine app infrastructure
        let appInfrastructure = """
// MARK: - Generated App Infrastructure

\(stateObjects)\(generatedInit)\(generatedBody)\(generatedDatabaseClass)
"""

        var members: [DeclSyntax] = [
            DeclSyntax(stringLiteral: shellView),
            DeclSyntax(stringLiteral: previews)
        ]

        // Add app infrastructure if we generated anything
        if !hasBody || !hasInit || useGeneratedDatabase {
            members.append(DeclSyntax(stringLiteral: appInfrastructure))
        }

        // Note: Extensions for Sheet/FullScreen/Window Identifiable conformance
        // must be added manually by the user since MemberMacro cannot generate extensions.
        // Add: extension Sheet: Identifiable { var id: String { String(describing: self) } }

        if let windowEnum {
            let windowBuilderCall = windowBuilderName ?? ""

            let windowScenes = """
#if os(macOS) || os(iOS)
\(access)struct ShellScenes: SwiftUI.Scene {
    private let container: EnvContainer
    private let windowBuilder: ((Window, EnvContainer) -> any SwiftUI.Scene)?

    init(container: EnvContainer = EnvContainer(), mergeFrom parent: EnvContainer? = nil, builder: ((Window, EnvContainer) -> any SwiftUI.Scene)? = nil) {
        var working = EnvContainer()
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

// MARK: - Tab Entitlement Support

private struct TabCaseInfo {
    let name: String
    let entitlement: TabEntitlementInfo?
}

private struct TabEntitlementInfo {
    enum RequirementType {
        case single
        case anyOf
        case allOf
    }

    let type: RequirementType
    let entitlements: [String]
    let behavior: String  // hidden, locked, disabled, limited
    let autoPaywall: Bool

    /// Generate the EntitlementRequirement expression
    func generateRequirementExpr() -> String {
        switch type {
        case .single:
            return ".required(.\(entitlements[0]))"
        case .anyOf:
            let list = entitlements.map { ".\($0)" }.joined(separator: ", ")
            return ".anyOf([\(list)])"
        case .allOf:
            let list = entitlements.map { ".\($0)" }.joined(separator: ", ")
            return ".allOf([\(list)])"
        }
    }
}

/// Extract entitlement requirement from @requires, @requiresAny, or @requiresAll attributes on Tab enum cases
private func extractTabEntitlement(from caseDecl: EnumCaseDeclSyntax) -> TabEntitlementInfo? {
    for attr in caseDecl.attributes {
        guard let attrSyntax = attr.as(AttributeSyntax.self) else { continue }
        let attrName = attrSyntax.attributeName.trimmedDescription

        guard ["requires", "requiresAny", "requiresAll"].contains(attrName) else { continue }

        var entitlements: [String] = []
        var autoPaywall = true
        var behavior = "locked"

        if let args = attrSyntax.arguments?.as(LabeledExprListSyntax.self) {
            for arg in args {
                let label = arg.label?.text

                if label == nil || label == "_" {
                    // Unlabeled argument - entitlement
                    if let memberAccess = arg.expression.as(MemberAccessExprSyntax.self) {
                        entitlements.append(memberAccess.declName.baseName.text)
                    }
                } else if label == "autoPaywall" {
                    if let boolLiteral = arg.expression.as(BooleanLiteralExprSyntax.self) {
                        autoPaywall = boolLiteral.literal.tokenKind == .keyword(.true)
                    }
                } else if label == "behavior" {
                    if let memberAccess = arg.expression.as(MemberAccessExprSyntax.self) {
                        behavior = memberAccess.declName.baseName.text
                    }
                }
            }
        }

        guard !entitlements.isEmpty else { continue }

        let type: TabEntitlementInfo.RequirementType
        switch attrName {
        case "requires": type = .single
        case "requiresAny": type = .anyOf
        case "requiresAll": type = .allOf
        default: continue
        }

        return TabEntitlementInfo(type: type, entitlements: entitlements, behavior: behavior, autoPaywall: autoPaywall)
    }
    return nil
}

// MARK: - Navigation Coordinator Generation

/// Generates the NavigationCoordinator subclass for the app
private func generateNavigationCoordinator(
    structName: String,
    tabCases: [String],
    tabCaseInfos: [TabCaseInfo],
    tabBuilders: [String: String],
    customRouteEnums: [String: String],
    access: String
) -> String {
    let firstTab = tabCases.first ?? "root"

    // Generate route resolution switch cases for each tab
    let routeResolutionCases = tabCases.map { name in
        let route = name.capitalizedRouteName
        let builderCall = tabBuilders[route].map { "\(structName).\($0)(route, container)" } ?? "AnyView(Text(String(describing: route)))"
        return """
                if let route = anyRoute.as(ShellView.\(route).self) {
                    return AnyView(\(builderCall))
                }
        """
    }.joined(separator: "\n")

    // Generate entitlement checking if tabs have requirements
    let hasEntitlements = tabCaseInfos.contains { $0.entitlement != nil }
    let entitlementCheck = hasEntitlements ? """

        open override func checkEntitlement<R: NavigationRoute>(for route: R) -> EntitlementRequirement? {
            // Check if the route identifier maps to a gated tab
            let identifier = route.navigationIdentifier
            for tab in Tab.allCases {
                let requirement = \(structName).tabRequirement(for: tab)
                if requirement != .none {
                    // Check if this route belongs to this tab's route enum
                    // Generated code would have more specific checks based on route types
                }
            }
            return nil
        }
    """ : ""

    // Generate deep link path patterns for each tab
    let deepLinkPatterns = tabCases.map { name in
        """
                case "\(name)":
                    guard let tab = tabForIndex(\(tabCases.firstIndex(of: name) ?? 0)) else { return .notFound }
                    var actions: [CoordinatorAction] = [.selectTab(index: \(tabCases.firstIndex(of: name) ?? 0))]
                    // Parse remaining path components as route parameters
                    if pathComponents.count > 1 {
                        // Route-specific parsing would go here
                    }
                    return .success(actions)
        """
    }.joined(separator: "\n")

    return """
/// Generated NavigationCoordinator for \(structName)
@MainActor
\(access)final class ShellNavigationCoordinator: NavigationCoordinator<\(structName).Tab> {
    private let container: EnvContainer

    \(access)init(container: EnvContainer = EnvContainer()) {
        self.container = container
        super.init(initialTab: .\(firstTab))
    }

    // MARK: - Route Resolution

    /// Resolve a type-erased route to its view
    \(access)func resolveView(for anyRoute: AnyRoute) -> AnyView {
\(routeResolutionCases)
        return AnyView(Text("Unknown route: \\(anyRoute.id)"))
    }

    // MARK: - Handle Factory

    open override func makeHandle(for context: PresentationContext) -> any NavigationHandle {
        // Create a context-aware handle
        ShellNavigationHandle(coordinator: self, context: context, container: container)
    }\(entitlementCheck)

    // MARK: - Deep Link Resolution

    open override func resolveDeepLink(_ url: URL) -> DeepLinkResolution? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return .invalidFormat("Could not parse URL")
        }

        let pathComponents = components.path.split(separator: "/").map(String.init)
        guard let firstPath = pathComponents.first else {
            return .notFound
        }

        // Check for flow deep links
        if firstPath == "flow" {
            guard pathComponents.count >= 2 else { return .notFound }
            let flowId = pathComponents[1]
            let step = pathComponents.count >= 4 && pathComponents[2] == "step" ? pathComponents[3] : nil
            return .flow(id: flowId, step: step)
        }

        // Route to tab
        switch firstPath {
\(deepLinkPatterns)
        default:
            return .notFound
        }
    }
}

/// Navigation handle used by the ShellNavigationCoordinator
@MainActor
\(access)final class ShellNavigationHandle: BaseNavigationHandle {
    private let container: EnvContainer

    init(coordinator: ShellNavigationCoordinator, context: PresentationContext, container: EnvContainer) {
        self.container = container
        super.init(coordinator: coordinator, context: context)
    }
}
"""
}

/// Generates a typed navigation handle protocol for a specific tab/feature
private func generateNavigationHandleProtocol(
    tabName: String,
    structName: String,
    access: String
) -> String {
    let protocolName = tabName.capitalizedFirst + "Navigation"
    let routeType = "ShellView.\(tabName.capitalizedRouteName)"

    return """
/// Typed navigation handle protocol for the \(tabName) feature.
///
/// Features inject this via environment and use its methods for navigation.
/// The feature doesn't know how routes are presented - that's controlled by @presents annotations.
///
/// Usage:
/// ```swift
/// struct \(tabName.capitalizedFirst)View: View {
///     @Environment(\\.\(tabName)Navigation) private var nav
///
///     var body: some View {
///         Button("Navigate") { nav.showDetail(id: "123") }
///     }
/// }
/// ```
@MainActor
\(access)protocol \(protocolName): NavigationHandle {
    /// Navigate to a route in the \(tabName) feature
    func navigate(to route: \(routeType))

    /// Navigate to a route with explicit presentation style
    func navigate(to route: \(routeType), style: PresentationStyle)

    /// Check if navigation to a route is allowed (entitlements)
    func canNavigate(to route: \(routeType)) -> Bool

    /// Navigate if allowed, showing paywall if blocked. Returns true if navigation succeeded.
    func navigateIfAllowed(to route: \(routeType)) async -> Bool
}

/// Default implementation for \(protocolName)
@MainActor
\(access)final class \(protocolName)Handle: BaseNavigationHandle, \(protocolName) {
    \(access)func navigate(to route: \(routeType)) {
        navigate(to: route)
    }

    \(access)func navigate(to route: \(routeType), style: PresentationStyle) {
        navigate(to: route, style: style)
    }

    \(access)func canNavigate(to route: \(routeType)) -> Bool {
        canNavigate(to: route.navigationIdentifier)
    }

    \(access)func navigateIfAllowed(to route: \(routeType)) async -> Bool {
        await navigateIfAllowed(to: route)
    }
}

/// Environment key for \(protocolName)
\(access)struct \(protocolName)Key: EnvironmentKey {
    nonisolated(unsafe) \(access)static let defaultValue: (any \(protocolName))? = nil
}

\(access)extension EnvironmentValues {
    var \(tabName)Navigation: (any \(protocolName))? {
        get { self[\(protocolName)Key.self] }
        set { self[\(protocolName)Key.self] = newValue }
    }
}
"""
}
