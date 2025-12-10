import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

// MARK: - @Route Macro
// Generates deep link URL pattern matching and auto-registration for route enums.
//
// Usage:
// @Route(path: "tasks")
// enum TasksRoute: NavigationRoute {
//     case list                           // matches /tasks/list
//     case detail(id: String)             // matches /tasks/:id
//     case filter(status: String, priority: String)  // matches /tasks/filter?status=X&priority=Y
// }
//
// Generates:
// - URL pattern matching
// - NavigationSerializable conformance
// - Static registration method for DeepLinkRouter

public struct RouteMacro: MemberMacro, ExtensionMacro {

    // MARK: - Member Macro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw RouteMacroError.notAnEnum
        }

        let config = parseConfig(from: node)
        let cases = extractCases(from: enumDecl)

        // Generate URL matching function
        let matcherDecl = generateURLMatcher(basePath: config.basePath, cases: cases)

        // Generate route -> URL function
        let urlBuilderDecl = generateURLBuilder(basePath: config.basePath, cases: cases)

        var members: [DeclSyntax] = [matcherDecl, urlBuilderDecl]

        // Generate entitlement methods if any cases have requirements OR route has requirement
        let hasEntitlements = config.routeRequirement != nil || cases.contains { $0.entitlementRequirement != nil }
        if hasEntitlements {
            members.append(generateEntitlementRequirementMethod(cases: cases, routeFallback: config.routeRequirement))
            members.append(generateAutoPaywallMethod(cases: cases, routeFallback: config.routeRequirement))
        }

        // Generate presentation style method if any cases have @presents
        let hasPresentation = cases.contains { $0.presentation != nil }
        if hasPresentation {
            members.append(generatePresentationStyleMethod(cases: cases))
            members.append(generatePresentationMetadataMethod(cases: cases))
        }

        return members
    }

    // MARK: - Presentation Generation

    private static func generatePresentationStyleMethod(cases: [RouteCase]) -> DeclSyntax {
        var switchCases: [String] = []

        for routeCase in cases {
            let styleExpr = routeCase.presentation?.generateStyleExpr() ?? ".push"

            if routeCase.parameters.isEmpty {
                switchCases.append("case .\(routeCase.name): return \(styleExpr)")
            } else {
                switchCases.append("case .\(routeCase.name): return \(styleExpr)")
            }
        }

        let switchBody = switchCases.joined(separator: "\n            ")

        return DeclSyntax(stringLiteral: """
            /// Returns the presentation style for a specific route case
            public nonisolated static func presentationStyle(for route: Self) -> Archery.PresentationStyle {
                switch route {
                \(switchBody)
                }
            }
        """)
    }

    private static func generatePresentationMetadataMethod(cases: [RouteCase]) -> DeclSyntax {
        var switchCases: [String] = []

        for routeCase in cases {
            let metadataExpr = routeCase.presentation?.generateMetadataExpr() ?? "PresentationMetadata()"

            if routeCase.parameters.isEmpty {
                switchCases.append("case .\(routeCase.name): return \(metadataExpr)")
            } else {
                switchCases.append("case .\(routeCase.name): return \(metadataExpr)")
            }
        }

        let switchBody = switchCases.joined(separator: "\n            ")

        return DeclSyntax(stringLiteral: """
            /// Returns the presentation metadata for a specific route case
            public nonisolated static func presentationMetadata(for route: Self) -> Archery.PresentationMetadata {
                switch route {
                \(switchBody)
                }
            }
        """)
    }

    // MARK: - Entitlement Generation

    private static func generateEntitlementRequirementMethod(cases: [RouteCase], routeFallback: EntitlementReq?) -> DeclSyntax {
        var switchCases: [String] = []
        let fallbackExpr = routeFallback?.generateRequirementExpr() ?? ".none"

        for routeCase in cases {
            // Case-level requirement takes precedence over route-level
            let requirement = routeCase.entitlementRequirement?.generateRequirementExpr() ?? fallbackExpr

            if routeCase.parameters.isEmpty {
                switchCases.append("case .\(routeCase.name): return \(requirement)")
            } else {
                switchCases.append("case .\(routeCase.name): return \(requirement)")
            }
        }

        let switchBody = switchCases.joined(separator: "\n            ")

        return DeclSyntax(stringLiteral: """
            /// Returns the entitlement requirement for a specific route case
            public nonisolated static func entitlementRequirement(for route: Self) -> Archery.EntitlementRequirement {
                switch route {
                \(switchBody)
                }
            }
        """)
    }

    private static func generateAutoPaywallMethod(cases: [RouteCase], routeFallback: EntitlementReq?) -> DeclSyntax {
        var switchCases: [String] = []
        let fallbackAutoPaywall = routeFallback?.autoPaywall ?? true

        for routeCase in cases {
            // Case-level takes precedence over route-level
            let autoPaywall = routeCase.entitlementRequirement?.autoPaywall ?? fallbackAutoPaywall

            if routeCase.parameters.isEmpty {
                switchCases.append("case .\(routeCase.name): return \(autoPaywall)")
            } else {
                switchCases.append("case .\(routeCase.name): return \(autoPaywall)")
            }
        }

        let switchBody = switchCases.joined(separator: "\n            ")

        return DeclSyntax(stringLiteral: """
            /// Returns whether the route should automatically present a paywall when blocked
            public nonisolated static func shouldAutoPaywall(for route: Self) -> Bool {
                switch route {
                \(switchBody)
                }
            }
        """)
    }

    // MARK: - Extension Macro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            return []
        }

        let typeName = enumDecl.name.text
        let config = parseConfig(from: node)

        // Generate NavigationSerializable required methods (without adding conformance)
        // User must add `: NavigationRoute` to their enum
        // Must be nonisolated for Sendable compatibility
        let serializableExt = try ExtensionDeclSyntax(
            """
            extension \(raw: typeName) {
                public nonisolated static func decodeNavigationIdentifier(_ value: String) -> Self? {
                    Self.fromURL(path: value.split(separator: "/").map(String.init), query: [:])
                }

                public nonisolated var navigationIdentifier: String {
                    toURLPath()
                }
            }
            """
        )

        // Generate registration helper
        let registrationExt = try ExtensionDeclSyntax(
            """
            extension \(raw: typeName) {
                public nonisolated static var routeBasePath: String { "\(raw: config.basePath)" }

                public nonisolated static func registerRoutes<R: NavigationRoute>(
                    in router: inout DeepLinkRouter<R>,
                    transform: @escaping @Sendable (Self) -> R?
                ) {
                    router.registerURL(path: "\(raw: config.basePath)") { components, params, query in
                        // Remove base path from components
                        let relevantPath = Array(components.dropFirst("\(raw: config.basePath)".split(separator: "/").count))
                        guard let route = Self.fromURL(path: relevantPath, query: query) else { return nil }
                        return transform(route)
                    }
                }
            }
            """
        )

        return [serializableExt, registrationExt]
    }

    // MARK: - Helpers

    private static func parseConfig(from node: AttributeSyntax) -> RouteConfig {
        var config = RouteConfig()

        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return config
        }

        var routeEntitlements: [String] = []
        var routeAutoPaywall = true

        for argument in arguments {
            let label = argument.label?.text

            if label == "path",
               let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
               let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                config.basePath = segment.content.text
            } else if label == "requires" {
                // Single entitlement: @Route(path: "x", requires: .premium)
                if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self) {
                    routeEntitlements.append(memberAccess.declName.baseName.text)
                }
            } else if label == "requiresAny" || label == "requiresAll" {
                // Array of entitlements: @Route(path: "x", requiresAny: [.premium, .pro])
                if let arrayExpr = argument.expression.as(ArrayExprSyntax.self) {
                    for element in arrayExpr.elements {
                        if let memberAccess = element.expression.as(MemberAccessExprSyntax.self) {
                            routeEntitlements.append(memberAccess.declName.baseName.text)
                        }
                    }
                }
                // Set the type based on label
                if label == "requiresAll" && !routeEntitlements.isEmpty {
                    config.routeRequirement = EntitlementReq(
                        type: .allOf,
                        entitlements: routeEntitlements,
                        autoPaywall: routeAutoPaywall
                    )
                    return config
                }
            } else if label == "autoPaywall" {
                if let boolLiteral = argument.expression.as(BooleanLiteralExprSyntax.self) {
                    routeAutoPaywall = boolLiteral.literal.tokenKind == .keyword(.true)
                }
            }
        }

        // Set route-level requirement if entitlements were found
        if !routeEntitlements.isEmpty {
            let type: EntitlementReq.RequirementType = routeEntitlements.count == 1 ? .single : .anyOf
            config.routeRequirement = EntitlementReq(
                type: type,
                entitlements: routeEntitlements,
                autoPaywall: routeAutoPaywall
            )
        }

        return config
    }

    private static func extractCases(from enumDecl: EnumDeclSyntax) -> [RouteCase] {
        var cases: [RouteCase] = []

        for member in enumDecl.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }

            // Extract entitlement requirements from case attributes
            let requirement = extractEntitlementRequirement(from: caseDecl)

            // Extract presentation style from @presents attribute
            let presentation = extractPresentationConfig(from: caseDecl)

            for element in caseDecl.elements {
                let name = element.name.text
                var params: [(name: String, type: String)] = []

                if let paramClause = element.parameterClause {
                    for (index, param) in paramClause.parameters.enumerated() {
                        let paramName = param.firstName?.text ?? "param\(index)"
                        let paramType = param.type.description.trimmingCharacters(in: .whitespaces)
                        params.append((paramName, paramType))
                    }
                }

                cases.append(RouteCase(
                    name: name,
                    parameters: params,
                    entitlementRequirement: requirement,
                    presentation: presentation
                ))
            }
        }

        return cases
    }

    /// Extract presentation configuration from @presents attribute
    private static func extractPresentationConfig(from caseDecl: EnumCaseDeclSyntax) -> PresentationConfig? {
        for attr in caseDecl.attributes {
            guard let attrSyntax = attr.as(AttributeSyntax.self) else { continue }
            let attrName = attrSyntax.attributeName.trimmedDescription

            guard attrName == "presents" else { continue }

            var style: PresentationConfig.Style = .push
            var detents: [String] = ["large"]
            var interactiveDismissDisabled = false

            if let args = attrSyntax.arguments?.as(LabeledExprListSyntax.self) {
                for arg in args {
                    let label = arg.label?.text

                    if label == nil || label == "_" {
                        // First unlabeled argument is the style
                        if let memberAccess = arg.expression.as(MemberAccessExprSyntax.self) {
                            let styleName = memberAccess.declName.baseName.text
                            style = PresentationConfig.Style(rawValue: styleName) ?? .push
                        }
                    } else if label == "detents" {
                        // Array of detents
                        if let arrayExpr = arg.expression.as(ArrayExprSyntax.self) {
                            detents = []
                            for element in arrayExpr.elements {
                                if let memberAccess = element.expression.as(MemberAccessExprSyntax.self) {
                                    detents.append(memberAccess.declName.baseName.text)
                                }
                            }
                        }
                    } else if label == "interactiveDismissDisabled" {
                        if let boolLiteral = arg.expression.as(BooleanLiteralExprSyntax.self) {
                            interactiveDismissDisabled = boolLiteral.literal.tokenKind == .keyword(.true)
                        }
                    }
                }
            }

            return PresentationConfig(
                style: style,
                detents: detents,
                interactiveDismissDisabled: interactiveDismissDisabled
            )
        }
        return nil
    }

    /// Extract entitlement requirement from @requires, @requiresAny, or @requiresAll attributes
    private static func extractEntitlementRequirement(from caseDecl: EnumCaseDeclSyntax) -> EntitlementReq? {
        for attr in caseDecl.attributes {
            guard let attrSyntax = attr.as(AttributeSyntax.self) else { continue }
            let attrName = attrSyntax.attributeName.trimmedDescription

            guard ["requires", "requiresAny", "requiresAll"].contains(attrName) else { continue }

            var entitlements: [String] = []
            var autoPaywall = true

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
                    }
                }
            }

            guard !entitlements.isEmpty else { continue }

            let type: EntitlementReq.RequirementType
            switch attrName {
            case "requires": type = .single
            case "requiresAny": type = .anyOf
            case "requiresAll": type = .allOf
            default: continue
            }

            return EntitlementReq(type: type, entitlements: entitlements, autoPaywall: autoPaywall)
        }
        return nil
    }

    private static func generateURLMatcher(basePath: String, cases: [RouteCase]) -> DeclSyntax {
        var ifClauses: [String] = []

        for routeCase in cases {
            if routeCase.parameters.isEmpty {
                // Simple case: /basePath/caseName
                ifClauses.append("""
                    if path == ["\(routeCase.name)"] {
                            return .\(routeCase.name)
                        }
                """)
            } else if routeCase.parameters.count == 1 {
                // Single param: /basePath/:param
                let param = routeCase.parameters[0]
                if param.type == "String" {
                    ifClauses.append("""
                        if path.count == 1 {
                                let \(param.name) = path[0]
                                return .\(routeCase.name)(\(param.name): \(param.name))
                            }
                    """)
                } else if param.type == "Int" {
                    ifClauses.append("""
                        if path.count == 1, let \(param.name) = Int(path[0]) {
                                return .\(routeCase.name)(\(param.name): \(param.name))
                            }
                    """)
                }
            } else {
                // Multiple params: use query string
                let queryExtract = routeCase.parameters.map { param in
                    if param.type == "String" {
                        return "let \(param.name) = query[\"\(param.name)\"]"
                    } else if param.type == "Int" {
                        return "let \(param.name)Str = query[\"\(param.name)\"], let \(param.name) = Int(\(param.name)Str)"
                    } else {
                        return "let \(param.name) = query[\"\(param.name)\"]"
                    }
                }.joined(separator: ", ")
                let paramAssign = routeCase.parameters.map { "\($0.name): \($0.name)" }.joined(separator: ", ")

                ifClauses.append("""
                    if path == ["\(routeCase.name)"], \(queryExtract) {
                            return .\(routeCase.name)(\(paramAssign))
                        }
                """)
            }
        }

        let ifBody = ifClauses.joined(separator: "\n        ")

        return DeclSyntax(stringLiteral: """
            public nonisolated static func fromURL(path: [String], query: [String: String]) -> Self? {
                \(ifBody)
                return nil
            }
        """)
    }

    private static func generateURLBuilder(basePath: String, cases: [RouteCase]) -> DeclSyntax {
        var buildCases: [String] = []

        for routeCase in cases {
            if routeCase.parameters.isEmpty {
                buildCases.append("""
                    case .\(routeCase.name):
                        return "\(basePath)/\(routeCase.name)"
                """)
            } else if routeCase.parameters.count == 1 {
                let param = routeCase.parameters[0]
                buildCases.append("""
                    case .\(routeCase.name)(let \(param.name)):
                        return "\(basePath)/\\(\(param.name))"
                """)
            } else {
                let paramPattern = routeCase.parameters.map { "let \($0.name)" }.joined(separator: ", ")
                let queryBuild = routeCase.parameters.map { "\($0.name)=\\(\($0.name))" }.joined(separator: "&")
                buildCases.append("""
                    case .\(routeCase.name)(\(paramPattern)):
                        return "\(basePath)/\(routeCase.name)?\(queryBuild)"
                """)
            }
        }

        let switchBody = buildCases.joined(separator: "\n            ")

        return DeclSyntax(stringLiteral: """
            public nonisolated func toURLPath() -> String {
                switch self {
                \(switchBody)
                }
            }
        """)
    }
}

private struct RouteConfig {
    var basePath: String = ""
    var routeRequirement: EntitlementReq?  // Route-level requirement applies to all cases
}

private struct RouteCase {
    let name: String
    let parameters: [(name: String, type: String)]
    let entitlementRequirement: EntitlementReq?
    let presentation: PresentationConfig?

    init(
        name: String,
        parameters: [(name: String, type: String)],
        entitlementRequirement: EntitlementReq? = nil,
        presentation: PresentationConfig? = nil
    ) {
        self.name = name
        self.parameters = parameters
        self.entitlementRequirement = entitlementRequirement
        self.presentation = presentation
    }
}

/// Configuration for @presents macro
private struct PresentationConfig {
    enum Style: String {
        case push, replace, sheet, fullScreen, popover, window
    }

    let style: Style
    let detents: [String]  // For sheet: ["medium", "large"]
    let interactiveDismissDisabled: Bool

    init(style: Style, detents: [String] = ["large"], interactiveDismissDisabled: Bool = false) {
        self.style = style
        self.detents = detents
        self.interactiveDismissDisabled = interactiveDismissDisabled
    }

    /// Generate the PresentationStyle expression
    func generateStyleExpr() -> String {
        switch style {
        case .push: return ".push"
        case .replace: return ".replace"
        case .sheet:
            let detentList = detents.map { ".\($0)" }.joined(separator: ", ")
            return ".sheet(detents: [\(detentList)])"
        case .fullScreen: return ".fullScreen"
        case .popover: return ".popover(edge: .top)"
        case .window: return ".window(id: \"default\")"
        }
    }

    /// Generate the PresentationMetadata expression
    func generateMetadataExpr() -> String {
        let styleExpr = generateStyleExpr()
        return "PresentationMetadata(style: \(styleExpr), dismissable: true, interactiveDismissDisabled: \(interactiveDismissDisabled))"
    }
}

/// Represents an entitlement requirement parsed from @requires attributes
private struct EntitlementReq {
    enum RequirementType {
        case single
        case anyOf
        case allOf
    }

    let type: RequirementType
    let entitlements: [String]
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

enum RouteMacroError: Error, CustomStringConvertible {
    case notAnEnum

    var description: String {
        switch self {
        case .notAnEnum:
            return "@Route can only be applied to enums"
        }
    }
}
