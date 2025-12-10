import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

// MARK: - @Entitled Macro

/// Member macro that adds entitlement requirement properties to a class.
/// Generates `requiredEntitlement` static property and `checkEntitlement()` method.
public struct EntitledMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(ClassDeclSyntax.self) || declaration.is(StructDeclSyntax.self) else {
            throw EntitledMacroError.invalidTarget
        }

        // Extract entitlement from arguments
        guard let entitlement = extractSingleEntitlement(from: node) else {
            throw EntitledMacroError.missingEntitlement
        }

        return generateMembers(requirement: ".required(.\(entitlement))")
    }
}

// MARK: - @EntitledAny Macro

/// Member macro for requiring ANY of the listed entitlements.
public struct EntitledAnyMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(ClassDeclSyntax.self) || declaration.is(StructDeclSyntax.self) else {
            throw EntitledMacroError.invalidTarget
        }

        let entitlements = extractMultipleEntitlements(from: node)
        guard !entitlements.isEmpty else {
            throw EntitledMacroError.missingEntitlement
        }

        let entitlementList = entitlements.map { ".\($0)" }.joined(separator: ", ")
        return generateMembers(requirement: ".anyOf([\(entitlementList)])")
    }
}

// MARK: - @EntitledAll Macro

/// Member macro for requiring ALL of the listed entitlements.
public struct EntitledAllMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(ClassDeclSyntax.self) || declaration.is(StructDeclSyntax.self) else {
            throw EntitledMacroError.invalidTarget
        }

        let entitlements = extractMultipleEntitlements(from: node)
        guard !entitlements.isEmpty else {
            throw EntitledMacroError.missingEntitlement
        }

        let entitlementList = entitlements.map { ".\($0)" }.joined(separator: ", ")
        return generateMembers(requirement: ".allOf([\(entitlementList)])")
    }
}

// MARK: - Shared Generation

private func generateMembers(requirement: String) -> [DeclSyntax] {
    return [
        """
        /// The entitlement requirement for this ViewModel
        public static let requiredEntitlement: Archery.EntitlementRequirement = \(raw: requirement)
        """,
        """
        /// Check if the current user has the required entitlement
        @MainActor
        public func checkEntitlement(store: Archery.StoreKitManager = .shared) -> Bool {
            Self.requiredEntitlement.isSatisfied(by: store.entitlements)
        }
        """
    ]
}

// MARK: - Argument Extraction

private func extractSingleEntitlement(from node: AttributeSyntax) -> String? {
    guard let args = node.arguments?.as(LabeledExprListSyntax.self),
          let firstArg = args.first,
          let memberAccess = firstArg.expression.as(MemberAccessExprSyntax.self) else {
        return nil
    }
    return memberAccess.declName.baseName.text
}

private func extractMultipleEntitlements(from node: AttributeSyntax) -> [String] {
    guard let args = node.arguments?.as(LabeledExprListSyntax.self) else {
        return []
    }

    return args.compactMap { arg in
        // Only unlabeled arguments (entitlements)
        guard arg.label == nil else { return nil }
        guard let memberAccess = arg.expression.as(MemberAccessExprSyntax.self) else { return nil }
        return memberAccess.declName.baseName.text
    }
}

// MARK: - Errors

enum EntitledMacroError: Error, CustomStringConvertible {
    case invalidTarget
    case missingEntitlement

    var description: String {
        switch self {
        case .invalidTarget:
            return "@Entitled, @EntitledAny, and @EntitledAll can only be applied to classes or structs"
        case .missingEntitlement:
            return "@Entitled requires at least one entitlement to be specified"
        }
    }
}
