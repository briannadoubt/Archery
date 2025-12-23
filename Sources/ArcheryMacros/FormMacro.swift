import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import Foundation

public struct FormMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Support both structs and classes
        let fields: [FieldInfo]
        let isClass: Bool

        if let structDecl = declaration.as(StructDeclSyntax.self) {
            fields = extractFields(from: structDecl.memberBlock)
            isClass = false
        } else if let classDecl = declaration.as(ClassDeclSyntax.self) {
            fields = extractFields(from: classDecl.memberBlock)
            isClass = true
        } else {
            return []
        }
        
        var members: [DeclSyntax] = []

        // Generate form container - different for class vs struct
        if isClass {
            members.append(DeclSyntax(stringLiteral: """
                @MainActor
                public lazy var formContainer: FormContainer = {
                    FormContainer(
                        fields: formFields,
                        onSubmit: { [weak self] in
                            try await self?.submit()
                        }
                    )
                }()
                """))
        } else {
            // For structs, provide a factory method since lazy var with closure doesn't work
            members.append(DeclSyntax(stringLiteral: """
                @MainActor
                public func makeFormContainer() -> FormContainer {
                    FormContainer(
                        fields: formFields,
                        onSubmit: { }
                    )
                }
                """))
        }
        
        // Generate form fields array
        let fieldInitializers = fields.map { field in
            generateFieldInitializer(for: field)
        }.joined(separator: ",\n        ")
        
        members.append(DeclSyntax(stringLiteral: """
            public var formFields: [any FormFieldProtocol] {
                [
                    \(fieldInitializers)
                ]
            }
            """))
        
        // Generate validation method
        members.append(DeclSyntax(stringLiteral: """
            public func validate() -> Bool {
                formContainer.validateAllFields()
                return formContainer.isValid
            }
            """))
        
        // Generate submit method
        members.append(DeclSyntax(stringLiteral: """
            public func submit() async throws {
                guard validate() else {
                    throw FormError.validationFailed(formContainer.errors)
                }
                // Override this method to implement submission logic
            }
            """))
        
        // Generate reset method
        members.append(DeclSyntax(stringLiteral: """
            public func reset() {
                formContainer.reset()
            }
            """))
        
        return members
    }
    
    private static func extractFields(from memberBlock: MemberBlockSyntax) -> [FieldInfo] {
        var fields: [FieldInfo] = []

        for member in memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  let binding = variable.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation?.type else {
                continue
            }
            
            let fieldName = identifier.identifier.text
            let fieldType = typeAnnotation.description.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let attributes = extractAttributes(from: variable.attributes)
            
            fields.append(FieldInfo(
                name: fieldName,
                type: fieldType,
                isRequired: attributes.isRequired,
                label: attributes.label ?? fieldName.camelCaseToWords(),
                placeholder: attributes.placeholder,
                helpText: attributes.helpText,
                validators: attributes.validators
            ))
        }
        
        return fields
    }
    
    private static func extractAttributes(from attributes: AttributeListSyntax) -> FieldAttributes {
        var fieldAttributes = FieldAttributes()
        
        for attribute in attributes {
            guard let attr = attribute.as(AttributeSyntax.self),
                  let identifier = attr.attributeName.as(IdentifierTypeSyntax.self) else {
                continue
            }
            
            switch identifier.name.text {
            case "Required":
                fieldAttributes.isRequired = true
                
            case "Label":
                if let arguments = attr.arguments?.as(LabeledExprListSyntax.self),
                   let stringLiteral = arguments.first?.expression.as(StringLiteralExprSyntax.self),
                   let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                    fieldAttributes.label = segment.content.text
                }
                
            case "Placeholder":
                if let arguments = attr.arguments?.as(LabeledExprListSyntax.self),
                   let stringLiteral = arguments.first?.expression.as(StringLiteralExprSyntax.self),
                   let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                    fieldAttributes.placeholder = segment.content.text
                }
                
            case "HelpText":
                if let arguments = attr.arguments?.as(LabeledExprListSyntax.self),
                   let stringLiteral = arguments.first?.expression.as(StringLiteralExprSyntax.self),
                   let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                    fieldAttributes.helpText = segment.content.text
                }
                
            case "Email":
                fieldAttributes.validators.append("EmailValidator()")
                
            case "URL":
                fieldAttributes.validators.append("URLValidator()")
                
            case "Phone":
                fieldAttributes.validators.append("PhoneValidator()")
                
            case "MinLength":
                if let arguments = attr.arguments?.as(LabeledExprListSyntax.self),
                   let intLiteral = arguments.first?.expression.as(IntegerLiteralExprSyntax.self) {
                    fieldAttributes.validators.append("MinLengthValidator(minLength: \(intLiteral))")
                }
                
            case "MaxLength":
                if let arguments = attr.arguments?.as(LabeledExprListSyntax.self),
                   let intLiteral = arguments.first?.expression.as(IntegerLiteralExprSyntax.self) {
                    fieldAttributes.validators.append("MaxLengthValidator(maxLength: \(intLiteral))")
                }
                
            default:
                break
            }
        }
        
        return fieldAttributes
    }
    
    private static func generateFieldInitializer(for field: FieldInfo) -> String {
        let fieldClass = determineFieldClass(for: field.type)
        
        var params: [String] = [
            "id: \"\(field.name)\"",
            "label: \"\(field.label)\"",
            "value: self.\(field.name)"
        ]
        
        if let placeholder = field.placeholder {
            params.append("placeholder: \"\(placeholder)\"")
        }
        
        if let helpText = field.helpText {
            params.append("helpText: \"\(helpText)\"")
        }
        
        if field.isRequired {
            params.append("isRequired: true")
        }
        
        if !field.validators.isEmpty {
            let validatorList = field.validators.joined(separator: ", ")
            params.append("validators: [\(validatorList)]")
        }
        
        return "\(fieldClass)(\n            \(params.joined(separator: ",\n            "))\n        )"
    }
    
    private static func determineFieldClass(for type: String) -> String {
        switch type {
        case "String", "String?":
            return "TextField"
        case "Int", "Int?", "Double", "Double?", "Float", "Float?":
            return "NumberField"
        case "Date", "Date?":
            return "DateField"
        case "Bool":
            return "BooleanField"
        default:
            return "FormField<\(type)>"
        }
    }
}

private struct FieldInfo {
    let name: String
    let type: String
    let isRequired: Bool
    let label: String
    let placeholder: String?
    let helpText: String?
    let validators: [String]
}

private struct FieldAttributes {
    var isRequired = false
    var label: String?
    var placeholder: String?
    var helpText: String?
    var validators: [String] = []
}

private extension String {
    func camelCaseToWords() -> String {
        return self.unicodeScalars.reduce("") { (result, scalar) in
            if CharacterSet.uppercaseLetters.contains(scalar) {
                return result + " " + String(scalar)
            } else {
                return result + String(scalar)
            }
        }.capitalized
    }
}