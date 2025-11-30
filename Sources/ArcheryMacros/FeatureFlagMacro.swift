import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import Foundation

public struct FeatureFlagMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.as(EnumDeclSyntax.self) != nil else {
            throw FeatureFlagMacroError.notAnEnum
        }
        
        // No member generation needed - flag types are created as extensions
        return []
    }
    
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw FeatureFlagMacroError.notAnEnum
        }
        
        var extensions: [ExtensionDeclSyntax] = []
        
        // Generate individual flag types for each case
        for member in enumDecl.memberBlock.members {
            if let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) {
                for element in caseDecl.elements {
                    let caseName = element.name.text
                    let flagTypeName = "\(caseName)Flag"
                    let key = caseName.camelCaseToKebabCase()
                    
                    // Extract default value from case parameters if present
                    let defaultValue = extractDefaultValue(from: element) ?? "false"
                    
                    let flagExtension = try ExtensionDeclSyntax(
                        """
                        public struct \(raw: flagTypeName): FeatureFlag {
                            public typealias Value = Bool
                            
                            public static var key: String {
                                "\(raw: key)"
                            }
                            
                            public static var defaultValue: Value {
                                \(raw: defaultValue)
                            }
                            
                            public static var description: String {
                                "Feature flag for \(raw: caseName)"
                            }
                        }
                        """
                    )
                    
                    extensions.append(flagExtension)
                }
            }
        }
        
        return extensions
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