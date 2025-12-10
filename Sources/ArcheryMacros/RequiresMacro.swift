import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

// MARK: - @requires Macro

/// Peer macro that marks an enum case as requiring a specific entitlement.
/// This macro doesn't generate code directly - it's metadata read by parent macros like @Route.
public struct RequiresMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Validate: can only be applied to enum cases
        guard declaration.is(EnumCaseDeclSyntax.self) else {
            throw RequiresMacroError.invalidTarget
        }

        // This is a marker macro - no code generation needed.
        // The @Route, @AppShell, and other macros read this attribute to extract requirements.
        return []
    }
}

// MARK: - @requiresAny Macro

/// Peer macro that marks content as requiring ANY of the listed entitlements (OR logic).
public struct RequiresAnyMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(EnumCaseDeclSyntax.self) else {
            throw RequiresMacroError.invalidTarget
        }
        return []
    }
}

// MARK: - @requiresAll Macro

/// Peer macro that marks content as requiring ALL of the listed entitlements (AND logic).
public struct RequiresAllMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(EnumCaseDeclSyntax.self) else {
            throw RequiresMacroError.invalidTarget
        }
        return []
    }
}

// MARK: - Attribute Parsing Utilities

/// Shared utilities for extracting entitlement information from @requires attributes.
public enum RequiresAttributeParser {

    /// Parsed result from a @requires, @requiresAny, or @requiresAll attribute
    public struct ParsedRequirement {
        public let type: RequirementType
        public let entitlements: [String]
        public let autoPaywall: Bool
        public let behavior: String

        public enum RequirementType {
            case single      // @requires
            case anyOf       // @requiresAny
            case allOf       // @requiresAll
        }
    }

    /// Extract requirement info from an attribute syntax node
    public static func parse(_ attr: AttributeSyntax) -> ParsedRequirement? {
        let attrName = attr.attributeName.trimmedDescription

        let type: ParsedRequirement.RequirementType
        switch attrName {
        case "requires":
            type = .single
        case "requiresAny":
            type = .anyOf
        case "requiresAll":
            type = .allOf
        default:
            return nil
        }

        var entitlements: [String] = []
        var autoPaywall = true
        var behavior = "locked"

        if let args = attr.arguments?.as(LabeledExprListSyntax.self) {
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

        guard !entitlements.isEmpty else { return nil }

        return ParsedRequirement(
            type: type,
            entitlements: entitlements,
            autoPaywall: autoPaywall,
            behavior: behavior
        )
    }

    /// Check if a declaration has any @requires-family attribute
    public static func hasRequiresAttribute(_ decl: some DeclSyntaxProtocol) -> Bool {
        guard let caseDecl = decl.as(EnumCaseDeclSyntax.self) else {
            return false
        }
        return caseDecl.attributes.contains { attr in
            guard let attrSyntax = attr.as(AttributeSyntax.self) else { return false }
            let name = attrSyntax.attributeName.trimmedDescription
            return name == "requires" || name == "requiresAny" || name == "requiresAll"
        }
    }

    /// Extract all @requires-family attributes from an enum case
    public static func extractRequirements(from caseDecl: EnumCaseDeclSyntax) -> [ParsedRequirement] {
        caseDecl.attributes.compactMap { attr in
            guard let attrSyntax = attr.as(AttributeSyntax.self) else { return nil }
            return parse(attrSyntax)
        }
    }
}

// MARK: - Errors

enum RequiresMacroError: Error, CustomStringConvertible {
    case invalidTarget

    var description: String {
        switch self {
        case .invalidTarget:
            return "@requires, @requiresAny, and @requiresAll can only be applied to enum cases"
        }
    }
}
