import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import Foundation

public struct AnalyticsEventMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw AnalyticsMacroError.notAnEnum
        }
        
        var members: [DeclSyntax] = []
        
        // Generate event name property
        members.append(
            """
            public var eventName: String {
                switch self {
                \(raw: generateEventNameCases(for: enumDecl))
                }
            }
            """
        )
        
        // Generate properties dictionary
        members.append(
            """
            public var properties: [String: Any] {
                switch self {
                \(raw: generatePropertiesCases(for: enumDecl))
                }
            }
            """
        )
        
        // Generate validation method
        members.append(
            """
            public func validate() throws {
                switch self {
                \(raw: generateValidationCases(for: enumDecl))
                }
            }
            """
        )
        
        return members
    }
    
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw AnalyticsMacroError.notAnEnum
        }
        
        let extensionDecl = try ExtensionDeclSyntax(
            """
            extension \(enumDecl.name): AnalyticsEvent {
                public func track(with provider: AnalyticsProvider) {
                    do {
                        try validate()
                        provider.track(eventName: eventName, properties: properties)
                    } catch {
                        print("[Analytics] Failed to track event: \\(error)")
                    }
                }
                
                public func redactedProperties() -> [String: Any] {
                    var redacted = properties
                    for (key, value) in redacted {
                        if isPII(key: key) {
                            redacted[key] = "[REDACTED]"
                        } else if let string = value as? String, containsPII(string) {
                            redacted[key] = redactPII(from: string)
                        }
                    }
                    return redacted
                }
                
                private func isPII(key: String) -> Bool {
                    let piiKeys = ["email", "phone", "ssn", "creditCard", "password", "token", "apiKey"]
                    return piiKeys.contains { key.lowercased().contains($0) }
                }
                
                private func containsPII(_ string: String) -> Bool {
                    // Check for email pattern
                    let emailRegex = try? NSRegularExpression(pattern: "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\\\.[A-Za-z]{2,64}")
                    if let matches = emailRegex?.matches(in: string, range: NSRange(string.startIndex..., in: string)),
                       !matches.isEmpty {
                        return true
                    }
                    
                    // Check for phone pattern
                    let phoneRegex = try? NSRegularExpression(pattern: "\\\\b\\\\d{3}[-.]?\\\\d{3}[-.]?\\\\d{4}\\\\b")
                    if let matches = phoneRegex?.matches(in: string, range: NSRange(string.startIndex..., in: string)),
                       !matches.isEmpty {
                        return true
                    }
                    
                    return false
                }
                
                private func redactPII(from string: String) -> String {
                    var result = string
                    
                    // Redact emails
                    if let emailRegex = try? NSRegularExpression(pattern: "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\\\.[A-Za-z]{2,64}") {
                        result = emailRegex.stringByReplacingMatches(
                            in: result,
                            range: NSRange(result.startIndex..., in: result),
                            withTemplate: "[EMAIL]"
                        )
                    }
                    
                    // Redact phone numbers
                    if let phoneRegex = try? NSRegularExpression(pattern: "\\\\b\\\\d{3}[-.]?\\\\d{3}[-.]?\\\\d{4}\\\\b") {
                        result = phoneRegex.stringByReplacingMatches(
                            in: result,
                            range: NSRange(result.startIndex..., in: result),
                            withTemplate: "[PHONE]"
                        )
                    }
                    
                    return result
                }
            }
            """
        )
        
        return [extensionDecl]
    }
    
    private static func generateEventNameCases(for enumDecl: EnumDeclSyntax) -> String {
        let cases = enumDecl.memberBlock.members.compactMap { member -> String? in
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { return nil }
            
            return caseDecl.elements.map { element in
                let caseName = element.name.text
                let eventName = caseName.camelCaseToSnakeCase()
                
                if element.parameterClause != nil {
                    return "case .\(caseName): return \"\(eventName)\""
                } else {
                    return "case .\(caseName): return \"\(eventName)\""
                }
            }.joined(separator: "\n")
        }.joined(separator: "\n")
        
        return cases
    }
    
    private static func generatePropertiesCases(for enumDecl: EnumDeclSyntax) -> String {
        let cases = enumDecl.memberBlock.members.compactMap { member -> String? in
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { return nil }
            
            return caseDecl.elements.map { element in
                let caseName = element.name.text
                
                if let params = element.parameterClause {
                    let properties = extractProperties(from: params)
                    if properties.isEmpty {
                        return "case .\(caseName): return [:]"
                    } else {
                        return "case let .\(caseName)(\(properties.map { $0.name }.joined(separator: ", "))): return [\(properties.map { "\"\($0.name)\": \($0.name)" }.joined(separator: ", "))]"
                    }
                } else {
                    return "case .\(caseName): return [:]"
                }
            }.joined(separator: "\n")
        }.joined(separator: "\n")
        
        return cases
    }
    
    private static func generateValidationCases(for enumDecl: EnumDeclSyntax) -> String {
        let cases = enumDecl.memberBlock.members.compactMap { member -> String? in
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { return nil }
            
            return caseDecl.elements.map { element in
                let caseName = element.name.text
                
                if let params = element.parameterClause {
                    let properties = extractProperties(from: params)
                    let validations = properties.compactMap { property -> String? in
                        generateValidation(for: property)
                    }
                    
                    if validations.isEmpty {
                        return "case .\(caseName): break"
                    } else {
                        return "case let .\(caseName)(\(properties.map { $0.name }.joined(separator: ", "))): \n\(validations.joined(separator: "\n"))"
                    }
                } else {
                    return "case .\(caseName): break"
                }
            }.joined(separator: "\n")
        }.joined(separator: "\n")
        
        return cases
    }
    
    private static func extractProperties(from params: EnumCaseParameterClauseSyntax) -> [(name: String, type: String)] {
        params.parameters.map { param in
            let name = param.firstName?.text ?? ""
            let type = param.type.description.trimmingCharacters(in: .whitespaces)
            return (name: name, type: type)
        }
    }
    
    private static func generateValidation(for property: (name: String, type: String)) -> String? {
        if property.type == "String" {
            return "    if \(property.name).isEmpty { throw AnalyticsError.invalidProperty(\"\(property.name) cannot be empty\") }"
        } else if property.type == "Int" || property.type == "Double" {
            return "    if \(property.name) < 0 { throw AnalyticsError.invalidProperty(\"\(property.name) cannot be negative\") }"
        }
        return nil
    }
}

extension String {
    func camelCaseToSnakeCase() -> String {
        return self.unicodeScalars.reduce("") { (result, scalar) in
            if CharacterSet.uppercaseLetters.contains(scalar) {
                return result + (result.isEmpty ? "" : "_") + String(scalar).lowercased()
            } else {
                return result + String(scalar)
            }
        }
    }
}

enum AnalyticsMacroError: Error, CustomStringConvertible {
    case notAnEnum
    
    var description: String {
        switch self {
        case .notAnEnum:
            return "@AnalyticsEvent can only be applied to enums"
        }
    }
}