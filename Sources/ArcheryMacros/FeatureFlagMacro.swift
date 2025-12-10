import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import Foundation

public struct FeatureFlagMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw FeatureFlagMacroError.notAnEnum
        }

        // Generate nested flag types as members
        var members: [DeclSyntax] = []

        for member in enumDecl.memberBlock.members {
            if let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) {
                for element in caseDecl.elements {
                    let caseName = element.name.text
                    let flagTypeName = "\(caseName.capitalizedFirst)Flag"
                    let key = caseName.camelCaseToKebabCase()

                    // Extract default value from case parameters if present
                    let defaultValue = extractDefaultValue(from: element) ?? "false"

                    members.append(
                        """
                        public struct \(raw: flagTypeName): Archery.FeatureFlag {
                            public typealias Value = Bool

                            public static var key: String { "\(raw: key)" }

                            public static var defaultValue: Value { \(raw: defaultValue) }

                            public static var description: String { "Feature flag for \(raw: caseName)" }
                        }
                        """
                    )
                }
            }
        }

        return members
    }
    
    private static func extractDefaultValue(from element: EnumCaseElementSyntax) -> String? {
        // Look for a default value in the case declaration
        // This is a simplified version - in production you'd parse more thoroughly
        if let params = element.parameterClause {
            let paramString = params.description
            if paramString.contains("default:") {
                if let defaultRange = paramString.range(of: "default:\\s*(true|false)", options: .regularExpression) {
                    return String(paramString[defaultRange]).replacingOccurrences(of: "default:", with: "").trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }
}

extension String {
    func camelCaseToKebabCase() -> String {
        return self.unicodeScalars.reduce("") { (result, scalar) in
            if CharacterSet.uppercaseLetters.contains(scalar) {
                return result + (result.isEmpty ? "" : "-") + String(scalar).lowercased()
            } else {
                return result + String(scalar)
            }
        }
    }

    var capitalizedFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

enum FeatureFlagMacroError: Error, CustomStringConvertible {
    case notAnEnum
    
    var description: String {
        switch self {
        case .notAnEnum:
            return "@FeatureFlag can only be applied to enums"
        }
    }
}