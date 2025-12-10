import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

struct LocalizableDiagnosticMessage: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity
}

public struct LocalizableMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            let diagnostic = Diagnostic(
                node: node,
                message: LocalizableDiagnosticMessage(
                    message: "@Localizable can only be applied to enums",
                    diagnosticID: MessageID(domain: "ArcheryMacros", id: "invalid-localizable-target"),
                    severity: .error
                )
            )
            context.diagnose(diagnostic)
            return []
        }
        
        var extractedStrings: [DeclSyntax] = []
        var localizedFunctions: [DeclSyntax] = []
        
        for member in enumDecl.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            
            for element in caseDecl.elements {
                let caseName = element.name.text
                let parameters = element.parameterClause?.parameters
                
                let localizedFunc = generateLocalizedFunction(
                    caseName: caseName,
                    parameters: parameters
                )
                localizedFunctions.append(localizedFunc)
                
                let stringExtraction = generateStringExtraction(
                    caseName: caseName,
                    enumName: enumDecl.name.text
                )
                extractedStrings.append(stringExtraction)
            }
        }
        
        let keyProperty = """
            public var key: String {
                switch self {
                \(enumDecl.memberBlock.members.compactMap { member -> String? in
                    guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { return nil }
                    return caseDecl.elements.map { element in
                        let caseName = element.name.text
                        if element.parameterClause != nil {
                            return "case .\(caseName): return \"\(enumDecl.name.text).\(caseName)\""
                        } else {
                            return "case .\(caseName): return \"\(enumDecl.name.text).\(caseName)\""
                        }
                    }.joined(separator: "\n")
                }.joined(separator: "\n"))
                }
            }
            """
        
        let localizedProperty = """
            public var localized: String {
                Archery.LocalizationEngine.shared.transform(
                    Bundle.main.localizedString(forKey: key, value: defaultValue, table: tableName)
                )
            }
            """
        
        let defaultValueProperty = """
            public var defaultValue: String {
                switch self {
                \(enumDecl.memberBlock.members.compactMap { member -> String? in
                    guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { return nil }
                    return caseDecl.elements.map { element in
                        let caseName = element.name.text
                        let humanized = caseName
                            .replacingOccurrences(of: "_", with: " ")
                            .split(separator: " ")
                            .map { $0.capitalized }
                            .joined(separator: " ")
                        return "case .\(caseName): return \"\(humanized)\""
                    }.joined(separator: "\n")
                }.joined(separator: "\n"))
                }
            }
            """
        
        let tableNameProperty = """
            public var tableName: String? {
                return "\(enumDecl.name.text)"
            }
            """
        
        let commentProperty = """
            public var comment: String {
                switch self {
                \(enumDecl.memberBlock.members.compactMap { member -> String? in
                    guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { return nil }
                    return caseDecl.elements.map { element in
                        let caseName = element.name.text
                        return "case .\(caseName): return \"Localized string for \(caseName)\""
                    }.joined(separator: "\n")
                }.joined(separator: "\n"))
                }
            }
            """
        
        return [
            DeclSyntax(stringLiteral: keyProperty),
            DeclSyntax(stringLiteral: localizedProperty),
            DeclSyntax(stringLiteral: defaultValueProperty),
            DeclSyntax(stringLiteral: tableNameProperty),
            DeclSyntax(stringLiteral: commentProperty),
        ] + localizedFunctions + extractedStrings
    }
    
    private static func generateLocalizedFunction(
        caseName: String,
        parameters: EnumCaseParameterListSyntax?
    ) -> DeclSyntax {
        // Use a prefixed name to avoid conflicts with enum cases
        let funcName = "localized\(caseName.prefix(1).uppercased())\(caseName.dropFirst())"

        if let parameters = parameters {
            let paramList = parameters.map { param in
                let label = param.firstName?.text ?? "_"
                let name = param.secondName?.text ?? param.firstName?.text ?? "arg"
                let type = param.type
                return "\(label) \(name): \(type)"
            }.joined(separator: ", ")

            let args = parameters.enumerated().map { index, _ in
                return "arg\(index)"
            }.joined(separator: ", ")

            return DeclSyntax(stringLiteral: """
                public static func \(funcName)(\(paramList)) -> String {
                    let key = "\(caseName)"
                    let format = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
                    return String(format: format, \(args))
                }
                """)
        } else {
            return DeclSyntax(stringLiteral: """
                public static var \(funcName): String {
                    let key = "\(caseName)"
                    return Archery.LocalizationEngine.shared.transform(
                        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
                    )
                }
                """)
        }
    }
    
    private static func generateStringExtraction(
        caseName: String,
        enumName: String
    ) -> DeclSyntax {
        let defaultValue = caseName
            .replacingOccurrences(of: "_", with: " ")
            .capitalized

        return DeclSyntax(stringLiteral: """
            #if DEBUG
            private static let _extract_\(caseName): Void = {
                Archery.LocalizationEngine.shared.recordExtractedString(
                    Archery.ExtractedString(
                        key: "\(enumName).\(caseName)",
                        defaultValue: "\(defaultValue)",
                        comment: "Localized string for \(caseName)",
                        tableName: "\(enumName)"
                    )
                )
            }()
            #endif
            """)
    }
}

extension LocalizableMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Don't add LocalizationKey conformance since it requires RawRepresentable
        // The generated member properties provide localization functionality directly
        return []
    }
}