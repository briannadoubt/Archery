import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import Foundation

// MARK: - Configuration Macro

public struct ConfigurationMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            return []
        }
        
        let structName = structDecl.name.text
        let attributes = extractMacroArguments(from: node)
        let properties = extractProperties(from: structDecl)
        
        var members: [DeclSyntax] = []
        
        // Generate configuration manager
        members.append(DeclSyntax(stringLiteral: generateConfigurationManager(
            structName: structName,
            attributes: attributes
        )))
        
        // Generate default values
        members.append(DeclSyntax(stringLiteral: generateDefaultValues(
            properties: properties
        )))
        
        // Generate validation
        members.append(DeclSyntax(stringLiteral: generateValidation(
            properties: properties,
            attributes: attributes
        )))
        
        // Generate configuration schema
        members.append(DeclSyntax(stringLiteral: generateSchema(
            structName: structName,
            properties: properties
        )))
        
        // Generate static property accessors for clean API
        for property in properties {
            members.append(DeclSyntax(stringLiteral: generateStaticAccessor(
                property: property
            )))
        }

        // Generate environment-specific getters
        for property in properties {
            if property.isEnvironmentSpecific {
                members.append(DeclSyntax(stringLiteral: generateEnvironmentGetter(
                    property: property
                )))
            }

            if property.isSecret {
                members.append(DeclSyntax(stringLiteral: generateSecretGetter(
                    property: property
                )))
            }
        }

        return members
    }

    private static func generateStaticAccessor(property: ConfigProperty) -> String {
        """
        @MainActor
        public static var \(property.name): \(property.type) {
            manager.current.\(property.name)
        }
        """
    }
    
    private static func extractMacroArguments(from node: AttributeSyntax) -> ConfigurationAttributes {
        var attributes = ConfigurationAttributes()
        
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return attributes
        }
        
        for argument in arguments {
            guard let label = argument.label?.text else { continue }
            
            switch label {
            case "environmentPrefix":
                if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                   let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                    attributes.environmentPrefix = segment.content.text
                }
            case "validateOnChange":
                if let boolLiteral = argument.expression.as(BooleanLiteralExprSyntax.self) {
                    attributes.validateOnChange = boolLiteral.literal.text == "true"
                }
            case "enableRemoteConfig":
                if let boolLiteral = argument.expression.as(BooleanLiteralExprSyntax.self) {
                    attributes.enableRemoteConfig = boolLiteral.literal.text == "true"
                }
            case "schema":
                if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                   let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                    attributes.schemaFile = segment.content.text
                }
            default:
                break
            }
        }
        
        return attributes
    }
    
    private static func extractProperties(from structDecl: StructDeclSyntax) -> [ConfigProperty] {
        var properties: [ConfigProperty] = []
        
        for member in structDecl.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  let binding = variable.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation?.type else {
                continue
            }
            
            let propertyName = identifier.identifier.text
            let propertyType = typeAnnotation.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let propertyAttributes = extractPropertyAttributes(from: variable.attributes)
            
            let property = ConfigProperty(
                name: propertyName,
                type: propertyType,
                defaultValue: propertyAttributes.defaultValue,
                isRequired: propertyAttributes.isRequired,
                isSecret: propertyAttributes.isSecret,
                isEnvironmentSpecific: propertyAttributes.isEnvironmentSpecific,
                validation: propertyAttributes.validation,
                description: propertyAttributes.description
            )
            
            properties.append(property)
        }
        
        return properties
    }
    
    private static func extractPropertyAttributes(from attributes: AttributeListSyntax) -> PropertyAttributes {
        var propertyAttrs = PropertyAttributes()
        
        for attribute in attributes {
            guard let attr = attribute.as(AttributeSyntax.self),
                  let identifier = attr.attributeName.as(IdentifierTypeSyntax.self) else {
                continue
            }
            
            switch identifier.name.text {
            case "DefaultValue":
                if let arguments = attr.arguments?.as(LabeledExprListSyntax.self),
                   let stringLiteral = arguments.first?.expression.as(StringLiteralExprSyntax.self),
                   let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                    propertyAttrs.defaultValue = segment.content.text
                }
                
            case "Required":
                propertyAttrs.isRequired = true
                
            case "Secret":
                propertyAttrs.isSecret = true
                
            case "EnvironmentSpecific":
                propertyAttrs.isEnvironmentSpecific = true
                
            case "Validate":
                if let arguments = attr.arguments?.as(LabeledExprListSyntax.self) {
                    for arg in arguments {
                        if let label = arg.label?.text,
                           let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
                           let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                            
                            switch label {
                            case "pattern":
                                propertyAttrs.validation.pattern = segment.content.text
                            case "range":
                                propertyAttrs.validation.range = segment.content.text
                            case "values":
                                propertyAttrs.validation.allowedValues = segment.content.text.split(separator: ",").map(String.init)
                            default:
                                break
                            }
                        }
                    }
                }
                
            case "Description":
                if let arguments = attr.arguments?.as(LabeledExprListSyntax.self),
                   let stringLiteral = arguments.first?.expression.as(StringLiteralExprSyntax.self),
                   let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                    propertyAttrs.description = segment.content.text
                }
                
            default:
                break
            }
        }
        
        return propertyAttrs
    }
    
    private static func generateConfigurationManager(
        structName: String,
        attributes: ConfigurationAttributes
    ) -> String {
        """
        @MainActor
        private static let manager: Archery.ConfigurationManager<\(structName)> = {
            Archery.ConfigurationManager<\(structName)>(
                environmentPrefix: "\(attributes.environmentPrefix)"
            )
        }()

        @MainActor
        public static func override(_ key: String, value: Any) {
            manager.override(key, value: value)
        }

        @MainActor
        public static func clearOverrides() {
            manager.clearOverrides()
        }

        @MainActor
        public static func refresh() async {
            await manager.refresh()
        }

        @MainActor
        public static func setupRemoteConfig(url: URL, refreshInterval: TimeInterval) {
            manager.setupRemoteConfig(url: url, refreshInterval: refreshInterval)
        }
        """
    }
    
    private static func generateDefaultValues(properties: [ConfigProperty]) -> String {
        let propertyInits = properties.map { property in
            if let defaultValue = property.defaultValue {
                return "\(property.name): \(formatDefaultValue(defaultValue, type: property.type))"
            } else {
                return "\(property.name): \(generateDefaultValueForType(property.type))"
            }
        }.joined(separator: ",\n            ")
        
        return """
        public static var defaultValues: Self {
            Self(
                \(propertyInits)
            )
        }
        """
    }
    
    private static func generateValidation(
        properties: [ConfigProperty],
        attributes: ConfigurationAttributes
    ) -> String {
        var validationRules: [String] = []

        for property in properties {
            if property.isRequired {
                validationRules.append("Archery.ValidationRule(path: \"\(property.name)\", type: .required)")
            }

            if let pattern = property.validation.pattern {
                validationRules.append("Archery.ValidationRule(path: \"\(property.name)\", type: .pattern(\"\(pattern)\"))")
            }

            if let range = property.validation.range {
                let components = range.split(separator: "...")
                if components.count == 2,
                   let min = Double(components[0]),
                   let max = Double(components[1]) {
                    validationRules.append("Archery.ValidationRule(path: \"\(property.name)\", type: .range(min: \(min), max: \(max)))")
                }
            }

            if !property.validation.allowedValues.isEmpty {
                let values = property.validation.allowedValues.map { "\"\($0)\"" }.joined(separator: ", ")
                validationRules.append("Archery.ValidationRule(path: \"\(property.name)\", type: .allowedValues([\(values)]))")
            }

            if property.isSecret {
                validationRules.append("Archery.ValidationRule(path: \"\(property.name)\", type: .secretReference)")
            }
        }

        let rulesString = validationRules.joined(separator: ",\n            ")

        return """
        public func validate() throws -> Bool {
            let validator = Archery.ConfigValidator()

            \(rulesString.isEmpty ? "" : """
            let rules: [Archery.ValidationRule] = [
                \(rulesString)
            ]

            for rule in rules {
                validator.addRule(rule)
            }
            """)

            let result = try validator.validate(self)
            if !result.isValid {
                throw Archery.ConfigurationError.validationFailed(result.report())
            }

            return true
        }

        @MainActor
        public static func validate() throws -> Bool {
            try manager.current.validate()
        }
        """
    }
    
    private static func generateSchema(
        structName: String,
        properties: [ConfigProperty]
    ) -> String {
        let propertySchemas = properties.map { property in
            var schemaParams: [String] = [
                "type: \"\(getSchemaType(property.type))\""
            ]
            
            if let description = property.description {
                schemaParams.append("description: \"\(description)\"")
            }
            
            if let defaultValue = property.defaultValue {
                schemaParams.append("defaultValue: \"\(defaultValue)\"")
            }
            
            if let pattern = property.validation.pattern {
                schemaParams.append("pattern: \"\(pattern)\"")
            }
            
            if !property.validation.allowedValues.isEmpty {
                let values = property.validation.allowedValues.map { "\"\($0)\"" }.joined(separator: ", ")
                schemaParams.append("allowedValues: [\(values)]")
            }
            
            if property.isEnvironmentSpecific {
                schemaParams.append("environmentSpecific: true")
            }
            
            if property.isSecret {
                schemaParams.append("secret: true")
            }
            
            return "\"\(property.name)\": Archery.PropertySchema(\(schemaParams.joined(separator: ", ")))"
        }.joined(separator: ",\n            ")

        let requiredProperties = properties.filter { $0.isRequired }.map { "\"\($0.name)\"" }
        let requiredString = requiredProperties.joined(separator: ", ")

        return """
        public static var schema: Archery.ConfigurationSchema {
            Archery.ConfigurationSchema(
                version: "1.0",
                properties: [
                    \(propertySchemas)
                ],
                required: [\(requiredString)]
            )
        }
        """
    }
    
    private static func generateEnvironmentGetter(property: ConfigProperty) -> String {
        """
        public var \(property.name)ForEnvironment: \(property.type) {
            switch Archery.ConfigurationEnvironment.current {
            case .production:
                return self.\(property.name)
            case .staging:
                return self.\(property.name)
            case .development, .demo, .test:
                return self.\(property.name)
            }
        }
        """
    }
    
    private static func generateSecretGetter(property: ConfigProperty) -> String {
        // Capitalize only the first letter, preserving rest of camelCase
        let capitalizedName = property.name.prefix(1).uppercased() + property.name.dropFirst()
        return """
        @MainActor
        public var resolved\(capitalizedName): String? {
            do {
                if let secret = try Archery.SecretsManager.shared.retrieve("\(property.name)") {
                    return secret.value
                }
                return nil
            } catch {
                return nil
            }
        }

        @MainActor
        public static var resolved\(capitalizedName): String? {
            manager.current.resolved\(capitalizedName)
        }
        """
    }
    
    private static func formatDefaultValue(_ value: String, type: String) -> String {
        switch type {
        case "String", "String?":
            return "\"\(value)\""
        case "Bool":
            return value.lowercased()
        case "Int", "Double", "Float":
            return value
        default:
            return "\"\(value)\""
        }
    }
    
    private static func generateDefaultValueForType(_ type: String) -> String {
        switch type {
        case "String":
            return "\"\""
        case "String?":
            return "nil"
        case "Int":
            return "0"
        case "Int?":
            return "nil"
        case "Double":
            return "0.0"
        case "Double?":
            return "nil"
        case "Bool":
            return "false"
        case "Bool?":
            return "nil"
        default:
            if type.hasSuffix("?") {
                return "nil"
            }
            return "\"\""
        }
    }
    
    private static func getSchemaType(_ swiftType: String) -> String {
        switch swiftType {
        case "String", "String?":
            return "string"
        case "Int", "Int?":
            return "integer"
        case "Double", "Double?", "Float", "Float?":
            return "number"
        case "Bool", "Bool?":
            return "boolean"
        default:
            return "string"
        }
    }
}

// MARK: - Supporting Types

private struct ConfigurationAttributes {
    var environmentPrefix = "APP"
    var validateOnChange = true
    var enableRemoteConfig = false
    var schemaFile: String?
}

private struct ConfigProperty {
    let name: String
    let type: String
    let defaultValue: String?
    let isRequired: Bool
    let isSecret: Bool
    let isEnvironmentSpecific: Bool
    let validation: ValidationConfig
    let description: String?
    
    init(
        name: String,
        type: String,
        defaultValue: String? = nil,
        isRequired: Bool = false,
        isSecret: Bool = false,
        isEnvironmentSpecific: Bool = false,
        validation: ValidationConfig = ValidationConfig(),
        description: String? = nil
    ) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
        self.isRequired = isRequired
        self.isSecret = isSecret
        self.isEnvironmentSpecific = isEnvironmentSpecific
        self.validation = validation
        self.description = description
    }
}

private struct PropertyAttributes {
    var defaultValue: String?
    var isRequired = false
    var isSecret = false
    var isEnvironmentSpecific = false
    var validation = ValidationConfig()
    var description: String?
}

private struct ValidationConfig {
    var pattern: String?
    var range: String?
    var allowedValues: [String] = []
}

// MARK: - Property Marker Macros
//
// These are no-op peer macros that mark properties for inspection by @Configuration.
// They don't generate any code themselves - @Configuration reads them during its expansion.

public struct SecretMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        [] // No-op: just a marker
    }
}

public struct EnvironmentSpecificMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        [] // No-op: just a marker
    }
}

public struct ValidateMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        [] // No-op: just a marker
    }
}

public struct DefaultValueMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        [] // No-op: just a marker
    }
}

public struct DescriptionMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        [] // No-op: just a marker
    }
}