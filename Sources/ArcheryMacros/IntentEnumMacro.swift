import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

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
            throw IntentEnumMacroError.notAnEnum
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

enum IntentEnumMacroError: Error, CustomStringConvertible {
    case notAnEnum

    var description: String {
        switch self {
        case .notAnEnum:
            return "@IntentEnum can only be applied to enums"
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
