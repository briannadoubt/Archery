import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

// MARK: - @IntentEntity Macro
// Generates AppEntity conformance and EntityQuery for use with App Intents

public struct IntentEntityMacro: MemberMacro, ExtensionMacro {

    // MARK: - Member Macro (no members needed - all in extension)

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw IntentMacroError.notAStruct("@IntentEntity")
        }

        // Find id property
        let hasId = structDecl.memberBlock.members.contains { member in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { return false }
            return varDecl.bindings.contains { binding in
                binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "id"
            }
        }

        guard hasId else {
            throw IntentMacroError.missingId
        }

        // No members generated - AppEntity conformance is in extension
        return []
    }

    // MARK: - Extension Macro (generates AppEntity properties without conformance)
    // User must add `: AppEntity` to their struct declaration and provide defaultQuery

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            return []
        }

        let typeName = structDecl.name.text
        let config = parseConfig(from: node)

        // Find the title/display property
        let displayProperty = findDisplayProperty(in: structDecl) ?? "id"

        // Generate AppEntity required properties (without adding conformance)
        // User must add `: AppEntity` to their struct and provide defaultQuery
        // All properties must be nonisolated for Sendable conformance
        let appEntityExtension = try ExtensionDeclSyntax(
            """
            extension \(raw: typeName) {
                public nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
                    TypeDisplayRepresentation(name: "\(raw: config.displayName ?? typeName)")
                }

                public nonisolated var displayRepresentation: DisplayRepresentation {
                    DisplayRepresentation(title: "\\(self.\(raw: displayProperty))")
                }
            }
            """
        )

        return [appEntityExtension]
    }

    // MARK: - Helpers

    private static func parseConfig(from node: AttributeSyntax) -> IntentEntityConfig {
        var config = IntentEntityConfig()

        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return config
        }

        for argument in arguments {
            guard let label = argument.label?.text else { continue }

            switch label {
            case "displayName":
                if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                   let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                    config.displayName = segment.content.text
                }
            case "idType":
                config.idType = argument.expression.description.trimmingCharacters(in: .whitespaces)
            default:
                break
            }
        }

        return config
    }

    private static func findDisplayProperty(in structDecl: StructDeclSyntax) -> String? {
        let preferredNames = ["title", "name", "displayName", "label", "description"]

        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            for binding in varDecl.bindings {
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                let name = identifier.identifier.text

                if preferredNames.contains(name) {
                    return name
                }
            }
        }

        return nil
    }
}

private struct IntentEntityConfig {
    var displayName: String?
    var idType: String = "String"
}

// MARK: - @IntentEnum Macro
// Generates AppEnum conformance for use with App Intents

public struct IntentEnumMacro: MemberMacro, ExtensionMacro {

    // MARK: - Member Macro (generates caseDisplayRepresentations)

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw IntentMacroError.notAnEnum("@IntentEnum")
        }

        // Collect all cases
        var cases: [(name: String, displayName: String)] = []

        for member in enumDecl.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }

            for element in caseDecl.elements {
                let caseName = element.name.text
                let displayName = caseName.camelCaseToTitleCase()
                cases.append((caseName, displayName))
            }
        }

        // Generate caseDisplayRepresentations - must be nonisolated for Sendable
        let caseRepresentations = cases.map { caseName, displayName in
            ".\(caseName): DisplayRepresentation(title: \"\(displayName)\")"
        }.joined(separator: ",\n            ")

        let caseDisplayDecl = """
            public nonisolated static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
                \(caseRepresentations)
            ]
            """

        return [DeclSyntax(stringLiteral: caseDisplayDecl)]
    }

    // MARK: - Extension Macro (generates AppEnum properties without conformance)
    // User must add `: AppEnum` to their enum declaration

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
        let config = parseEnumConfig(from: node)

        // Generate AppEnum required properties (without adding conformance)
        // User must add `: AppEnum` to their enum declaration
        let appEnumExtension = try ExtensionDeclSyntax(
            """
            extension \(raw: typeName) {
                public nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
                    TypeDisplayRepresentation(name: "\(raw: config.displayName ?? typeName)")
                }
            }
            """
        )

        return [appEnumExtension]
    }

    private static func parseEnumConfig(from node: AttributeSyntax) -> IntentEnumConfig {
        var config = IntentEnumConfig()

        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return config
        }

        for argument in arguments {
            if argument.label?.text == "displayName",
               let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
               let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                config.displayName = segment.content.text
            }
        }

        return config
    }
}

private struct IntentEnumConfig {
    var displayName: String?
}

// MARK: - Errors

enum IntentMacroError: Error, CustomStringConvertible {
    case notAStruct(String)
    case notAnEnum(String)
    case missingId

    var description: String {
        switch self {
        case .notAStruct(let macro):
            return "\(macro) can only be applied to structs"
        case .notAnEnum(let macro):
            return "\(macro) can only be applied to enums"
        case .missingId:
            return "@IntentEntity requires the type to have an 'id' property"
        }
    }
}

// MARK: - String Extension

extension String {
    func camelCaseToTitleCase() -> String {
        var result = ""
        for (index, char) in self.enumerated() {
            if char.isUppercase && index > 0 {
                result += " "
            }
            if index == 0 {
                result += char.uppercased()
            } else {
                result += String(char)
            }
        }
        return result
    }
}
