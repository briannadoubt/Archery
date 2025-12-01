import Foundation

#if canImport(AppIntents)
import AppIntents

// MARK: - Intent Parameter Processor

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public final class IntentParameterProcessor {
    
    private let validator: IntentParameterValidator
    private let extractor: IntentParameterExtractor
    
    public init() {
        self.validator = IntentParameterValidator()
        self.extractor = IntentParameterExtractor()
    }
    
    /// Process and validate all parameters for an intent
    public func process<Intent: AppIntent>(
        intent: Intent,
        context: IntentProcessingContext
    ) async throws -> ProcessedParameters {
        
        let extractedParams = try extractor.extractParameters(from: intent)
        let validatedParams = try await validator.validate(
            parameters: extractedParams,
            context: context
        )
        
        return ProcessedParameters(
            original: extractedParams,
            validated: validatedParams,
            context: context
        )
    }
}

// MARK: - Intent Parameter Extractor

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public final class IntentParameterExtractor {
    
    /// Extract all parameters from an intent using reflection
    public func extractParameters<Intent: AppIntent>(from intent: Intent) throws -> [String: Any] {
        var parameters: [String: Any] = [:]
        
        let mirror = Mirror(reflecting: intent)
        
        for child in mirror.children {
            guard let label = child.label else { continue }
            
            // Skip computed properties and metadata
            if label.hasPrefix("_") || label.hasPrefix("$") {
                continue
            }
            
            parameters[label] = extractValue(child.value)
        }
        
        return parameters
    }
    
    private func extractValue(_ value: Any) -> Any {
        // Handle optional values
        if let optional = value as? any OptionalProtocol {
            return optional.wrappedValue ?? NSNull()
        }
        
        // Handle app entities
        if let entity = value as? any AppEntity {
            return EntityWrapper(entity: entity)
        }
        
        // Handle arrays of entities
        if let entityArray = value as? [any AppEntity] {
            return entityArray.map { EntityWrapper(entity: $0) }
        }
        
        // Return value as-is for primitive types
        return value
    }
}

// MARK: - Intent Parameter Validator

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public final class IntentParameterValidator {
    
    private var validationRules: [String: [ParameterValidationRule]] = [:]
    
    /// Register validation rules for specific parameter names
    public func register(rules: [ParameterValidationRule], forParameter name: String) {
        validationRules[name] = rules
    }
    
    /// Validate extracted parameters
    public func validate(
        parameters: [String: Any],
        context: IntentProcessingContext
    ) async throws -> [String: Any] {
        
        var validatedParameters: [String: Any] = [:]
        
        for (key, value) in parameters {
            let rules = validationRules[key] ?? []
            let validatedValue = try await validateParameter(
                name: key,
                value: value,
                rules: rules,
                context: context
            )
            validatedParameters[key] = validatedValue
        }
        
        return validatedParameters
    }
    
    private func validateParameter(
        name: String,
        value: Any,
        rules: [ParameterValidationRule],
        context: IntentProcessingContext
    ) async throws -> Any {
        
        var currentValue = value
        
        for rule in rules {
            currentValue = try await rule.validate(
                name: name,
                value: currentValue,
                context: context
            )
        }
        
        return currentValue
    }
}

// MARK: - Parameter Validation Rules

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public protocol ParameterValidationRule {
    func validate(
        name: String,
        value: Any,
        context: IntentProcessingContext
    ) async throws -> Any
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct RequiredParameterRule: ParameterValidationRule {
    
    public init() {}
    
    public func validate(
        name: String,
        value: Any,
        context: IntentProcessingContext
    ) async throws -> Any {
        
        if value is NSNull || (value as? any OptionalProtocol)?.isNil == true {
            throw IntentError.missingParameter(name)
        }
        
        return value
    }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct StringLengthRule: ParameterValidationRule {
    
    private let minLength: Int
    private let maxLength: Int
    
    public init(minLength: Int = 0, maxLength: Int = Int.max) {
        self.minLength = minLength
        self.maxLength = maxLength
    }
    
    public func validate(
        name: String,
        value: Any,
        context: IntentProcessingContext
    ) async throws -> Any {
        
        guard let stringValue = value as? String else {
            return value
        }
        
        if stringValue.count < minLength {
            throw IntentError.invalidParameter("\(name) must be at least \(minLength) characters")
        }
        
        if stringValue.count > maxLength {
            throw IntentError.invalidParameter("\(name) must be no more than \(maxLength) characters")
        }
        
        return stringValue
    }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct NumericRangeRule: ParameterValidationRule {
    
    private let minValue: Double
    private let maxValue: Double
    
    public init(minValue: Double = -Double.infinity, maxValue: Double = Double.infinity) {
        self.minValue = minValue
        self.maxValue = maxValue
    }
    
    public func validate(
        name: String,
        value: Any,
        context: IntentProcessingContext
    ) async throws -> Any {
        
        let numericValue: Double
        
        switch value {
        case let double as Double:
            numericValue = double
        case let int as Int:
            numericValue = Double(int)
        case let float as Float:
            numericValue = Double(float)
        default:
            return value
        }
        
        if numericValue < minValue {
            throw IntentError.invalidParameter("\(name) must be at least \(minValue)")
        }
        
        if numericValue > maxValue {
            throw IntentError.invalidParameter("\(name) must be no more than \(maxValue)")
        }
        
        return value
    }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct EmailValidationRule: ParameterValidationRule {
    
    public init() {}
    
    public func validate(
        name: String,
        value: Any,
        context: IntentProcessingContext
    ) async throws -> Any {
        
        guard let email = value as? String else {
            return value
        }
        
        let emailRegex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        
        if !emailPredicate.evaluate(with: email) {
            throw IntentError.invalidParameter("\(name) must be a valid email address")
        }
        
        return email
    }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct EntityExistenceRule: ParameterValidationRule {
    
    private let repository: any DataRepository
    
    public init(repository: any DataRepository) {
        self.repository = repository
    }
    
    public func validate(
        name: String,
        value: Any,
        context: IntentProcessingContext
    ) async throws -> Any {
        
        guard let entityWrapper = value as? EntityWrapper else {
            return value
        }
        
        // Check if entity exists in repository
        let exists = try await checkEntityExists(entityWrapper.entity)
        
        if !exists {
            throw IntentError.invalidParameter("\(name) does not exist")
        }
        
        return value
    }
    
    private func checkEntityExists(_ entity: any AppEntity) async throws -> Bool {
        // This would need to be implemented based on specific repository type
        // For now, assume it exists if it has an ID
        return !entity.id.isEmpty
    }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct AuthorizationRule: ParameterValidationRule {
    
    private let requiredPermission: String
    
    public init(requiredPermission: String) {
        self.requiredPermission = requiredPermission
    }
    
    public func validate(
        name: String,
        value: Any,
        context: IntentProcessingContext
    ) async throws -> Any {
        
        let isAuthorized = await checkAuthorization(
            permission: requiredPermission,
            context: context
        )
        
        if !isAuthorized {
            throw IntentError.authenticationRequired
        }
        
        return value
    }
    
    private func checkAuthorization(
        permission: String,
        context: IntentProcessingContext
    ) async -> Bool {
        // Check user authorization for this parameter
        // This would integrate with your auth system
        return context.isAuthenticated
    }
}

// MARK: - Intent Processing Context

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct IntentProcessingContext {
    public let isAuthenticated: Bool
    public let userId: String?
    public let deviceType: String
    public let timestamp: Date
    public let container: EnvContainer
    
    public init(
        isAuthenticated: Bool = false,
        userId: String? = nil,
        deviceType: String = "unknown",
        container: EnvContainer = .shared
    ) {
        self.isAuthenticated = isAuthenticated
        self.userId = userId
        self.deviceType = deviceType
        self.timestamp = Date()
        self.container = container
    }
}

// MARK: - Processed Parameters

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct ProcessedParameters {
    public let original: [String: Any]
    public let validated: [String: Any]
    public let context: IntentProcessingContext
    
    /// Get a validated parameter value
    public func value<T>(for key: String, as type: T.Type) -> T? {
        return validated[key] as? T
    }
    
    /// Get a required validated parameter value
    public func requiredValue<T>(for key: String, as type: T.Type) throws -> T {
        guard let value = validated[key] as? T else {
            throw IntentError.missingParameter(key)
        }
        return value
    }
    
    /// Get an entity parameter
    public func entity<T: AppEntity>(for key: String, as type: T.Type) -> T? {
        guard let wrapper = validated[key] as? EntityWrapper else {
            return nil
        }
        return wrapper.entity as? T
    }
}

// MARK: - Helper Types

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct EntityWrapper {
    public let entity: any AppEntity
    
    public init(entity: any AppEntity) {
        self.entity = entity
    }
}

protocol OptionalProtocol {
    var isNil: Bool { get }
    var wrappedValue: Any? { get }
}

extension Optional: OptionalProtocol {
    var isNil: Bool {
        return self == nil
    }
    
    var wrappedValue: Any? {
        return self
    }
}

// MARK: - Parameter Builder DSL

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
@resultBuilder
public struct ParameterValidationBuilder {
    public static func buildBlock(_ rules: ParameterValidationRule...) -> [ParameterValidationRule] {
        rules
    }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public extension IntentParameterValidator {
    
    /// Register validation rules using a builder
    func register(
        forParameter name: String,
        @ParameterValidationBuilder rules: () -> [ParameterValidationRule]
    ) {
        register(rules: rules(), forParameter: name)
    }
}

// MARK: - Common Validation Patterns

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct CommonValidations {
    
    /// Required string with length constraints
    public static func requiredString(minLength: Int = 1, maxLength: Int = 255) -> [ParameterValidationRule] {
        [
            RequiredParameterRule(),
            StringLengthRule(minLength: minLength, maxLength: maxLength)
        ]
    }
    
    /// Optional email validation
    public static func optionalEmail() -> [ParameterValidationRule] {
        [EmailValidationRule()]
    }
    
    /// Required email validation
    public static func requiredEmail() -> [ParameterValidationRule] {
        [
            RequiredParameterRule(),
            EmailValidationRule()
        ]
    }
    
    /// Positive number validation
    public static func positiveNumber() -> [ParameterValidationRule] {
        [
            RequiredParameterRule(),
            NumericRangeRule(minValue: 0)
        ]
    }
    
    /// Authorization required for parameter
    public static func requiresAuth(permission: String) -> [ParameterValidationRule] {
        [
            RequiredParameterRule(),
            AuthorizationRule(requiredPermission: permission)
        ]
    }
}

#endif