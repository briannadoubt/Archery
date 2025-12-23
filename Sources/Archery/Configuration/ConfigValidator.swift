import Foundation

// MARK: - Configuration Validator

public final class ConfigValidator {
    private var rules: [ValidationRule] = []
    private var customValidators: [String: (Any) -> Bool] = [:]
    
    public init() {}
    
    // MARK: - Rule Registration
    
    public func addRule(_ rule: ValidationRule) {
        rules.append(rule)
    }
    
    public func addCustomValidator(name: String, validator: @escaping (Any) -> Bool) {
        customValidators[name] = validator
    }
    
    // MARK: - Validation
    
    public func validate<T: Configuration>(_ config: T) throws -> ValidationResult {
        var errors: [ConfigValidationError] = []
        var warnings: [ConfigValidationError] = []
        
        // Convert to dictionary for validation
        guard let data = try? JSONEncoder().encode(config),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigurationError.validationFailed("Failed to serialize configuration")
        }
        
        // Run validation rules
        for rule in rules {
            do {
                try validateRule(rule, against: dict, path: "")
            } catch let error as ConfigValidationError {
                if error.severity == .error {
                    errors.append(error)
                } else {
                    warnings.append(error)
                }
            }
        }
        
        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
    
    private func validateRule(_ rule: ValidationRule, against dict: [String: Any], path: String) throws {
        let fullPath = path.isEmpty ? rule.path : "\(path).\(rule.path)"
        let value = getValue(from: dict, path: rule.path)
        
        switch rule.type {
        case .required:
            if value == nil {
                throw ConfigValidationError(
                    path: fullPath,
                    message: rule.message ?? "Required field is missing",
                    severity: rule.severity ?? .error
                )
            }
            
        case .type(let expectedType):
            if let value = value {
                if !isCorrectType(value, expectedType: expectedType) {
                    throw ConfigValidationError(
                        path: fullPath,
                        message: rule.message ?? "Expected type \(expectedType)",
                        severity: rule.severity ?? .error
                    )
                }
            }
            
        case .range(let min, let max):
            if let numberValue = value as? NSNumber {
                let doubleValue = numberValue.doubleValue
                if doubleValue < min || doubleValue > max {
                    throw ConfigValidationError(
                        path: fullPath,
                        message: rule.message ?? "Value must be between \(min) and \(max)",
                        severity: rule.severity ?? .error
                    )
                }
            }
            
        case .length(let minLength, let maxLength):
            if let stringValue = value as? String {
                if stringValue.count < minLength || stringValue.count > maxLength {
                    throw ConfigValidationError(
                        path: fullPath,
                        message: rule.message ?? "Length must be between \(minLength) and \(maxLength)",
                        severity: rule.severity ?? .error
                    )
                }
            }
            
        case .pattern(let pattern):
            if let stringValue = value as? String {
                if stringValue.range(of: pattern, options: .regularExpression) == nil {
                    throw ConfigValidationError(
                        path: fullPath,
                        message: rule.message ?? "Value does not match pattern",
                        severity: rule.severity ?? .error
                    )
                }
            }
            
        case .allowedValues(let values):
            if let value = value {
                let stringValue = String(describing: value)
                if !values.contains(stringValue) {
                    throw ConfigValidationError(
                        path: fullPath,
                        message: rule.message ?? "Value must be one of: \(values.joined(separator: ", "))",
                        severity: rule.severity ?? .error
                    )
                }
            }
            
        case .custom(let validatorName):
            if let value = value,
               let validator = customValidators[validatorName],
               !validator(value) {
                throw ConfigValidationError(
                    path: fullPath,
                    message: rule.message ?? "Custom validation failed",
                    severity: rule.severity ?? .error
                )
            }
            
        case .url:
            if let stringValue = value as? String,
               URL(string: stringValue) == nil {
                throw ConfigValidationError(
                    path: fullPath,
                    message: rule.message ?? "Invalid URL format",
                    severity: rule.severity ?? .error
                )
            }
            
        case .email:
            if let stringValue = value as? String {
                let emailPattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
                if stringValue.range(of: emailPattern, options: .regularExpression) == nil {
                    throw ConfigValidationError(
                        path: fullPath,
                        message: rule.message ?? "Invalid email format",
                        severity: rule.severity ?? .error
                    )
                }
            }
            
        case .secretReference:
            if let stringValue = value as? String {
                // Check if it's a secret reference (e.g., "${SECRET_NAME}")
                if stringValue.hasPrefix("${") && stringValue.hasSuffix("}") {
                    let secretKey = String(stringValue.dropFirst(2).dropLast())
                    // Note: Secret validation is skipped in sync context
                    // For full validation, use async validateSecrets method
                    _ = secretKey
                }
            }
            
        case .environmentSpecific(let allowedEnvironments):
            let currentEnv = ConfigurationEnvironment.current.rawValue
            if !allowedEnvironments.contains(currentEnv) {
                throw ConfigValidationError(
                    path: fullPath,
                    message: rule.message ?? "Not allowed in environment: \(currentEnv)",
                    severity: rule.severity ?? .warning
                )
            }
        }
    }
    
    private func getValue(from dict: [String: Any], path: String) -> Any? {
        let components = path.split(separator: ".").map(String.init)
        var current: Any? = dict
        
        for component in components {
            guard let currentDict = current as? [String: Any] else {
                return nil
            }
            current = currentDict[component]
        }
        
        return current
    }
    
    private func isCorrectType(_ value: Any, expectedType: ValidationRule.ValueType) -> Bool {
        switch expectedType {
        case .string:
            return value is String
        case .int:
            return value is Int || value is NSNumber
        case .double:
            return value is Double || value is NSNumber
        case .bool:
            return value is Bool
        case .array:
            return value is [Any]
        case .object:
            return value is [String: Any]
        }
    }
}

// MARK: - Validation Rule

public struct ValidationRule {
    public let path: String
    public let type: RuleType
    public let message: String?
    public let severity: ValidationSeverity?
    
    public init(
        path: String,
        type: RuleType,
        message: String? = nil,
        severity: ValidationSeverity? = .error
    ) {
        self.path = path
        self.type = type
        self.message = message
        self.severity = severity
    }
    
    public enum RuleType {
        case required
        case type(ValueType)
        case range(min: Double, max: Double)
        case length(min: Int, max: Int)
        case pattern(String)
        case allowedValues([String])
        case custom(String)
        case url
        case email
        case secretReference
        case environmentSpecific([String])
    }
    
    public enum ValueType {
        case string
        case int
        case double
        case bool
        case array
        case object
    }
}

// MARK: - Validation Result

public struct ValidationResult {
    public let isValid: Bool
    public let errors: [ConfigValidationError]
    public let warnings: [ConfigValidationError]
    
    public var hasWarnings: Bool {
        !warnings.isEmpty
    }
    
    public func report() -> String {
        var lines: [String] = []
        
        if !errors.isEmpty {
            lines.append("Errors:")
            for error in errors {
                lines.append("  ❌ \(error.path): \(error.message)")
            }
        }
        
        if !warnings.isEmpty {
            lines.append("Warnings:")
            for warning in warnings {
                lines.append("  ⚠️  \(warning.path): \(warning.message)")
            }
        }
        
        if isValid && !hasWarnings {
            lines.append("✅ Configuration is valid")
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - Validation Error

public struct ConfigValidationError: Error, Sendable {
    public let path: String
    public let message: String
    public let severity: ValidationSeverity

    public init(path: String, message: String, severity: ValidationSeverity = .error) {
        self.path = path
        self.message = message
        self.severity = severity
    }
}

public enum ValidationSeverity: Sendable {
    case error
    case warning
}

// MARK: - Default Validation Rules

public extension ConfigValidator {
    static func createDefault() -> ConfigValidator {
        let validator = ConfigValidator()
        
        // Common validation rules
        validator.addRule(ValidationRule(
            path: "apiUrl",
            type: .url,
            message: "API URL must be a valid URL"
        ))
        
        validator.addRule(ValidationRule(
            path: "apiTimeout",
            type: .range(min: 1, max: 300),
            message: "API timeout must be between 1 and 300 seconds"
        ))
        
        validator.addRule(ValidationRule(
            path: "logLevel",
            type: .allowedValues(["trace", "debug", "info", "warning", "error", "critical"]),
            message: "Log level must be one of the allowed values"
        ))
        
        // Environment-specific rules
        validator.addRule(ValidationRule(
            path: "debugMode",
            type: .environmentSpecific(["dev", "test"]),
            message: "Debug mode should only be enabled in development",
            severity: .warning
        ))
        
        validator.addRule(ValidationRule(
            path: "database.ssl",
            type: .environmentSpecific(["prod", "stage"]),
            message: "SSL should be enabled in production environments",
            severity: .error
        ))
        
        // Custom validators
        validator.addCustomValidator(name: "positiveNumber") { value in
            guard let number = value as? NSNumber else { return false }
            return number.doubleValue > 0
        }
        
        validator.addCustomValidator(name: "validPort") { value in
            guard let number = value as? NSNumber else { return false }
            let port = number.intValue
            return port > 0 && port <= 65535
        }
        
        return validator
    }
}

// MARK: - Configuration Schema

public struct ConfigurationSchema: Codable {
    public let version: String
    public let properties: [String: PropertySchema]
    public let required: [String]
    
    public init(version: String, properties: [String: PropertySchema], required: [String] = []) {
        self.version = version
        self.properties = properties
        self.required = required
    }
}

public struct PropertySchema: Codable {
    public let type: String
    public let description: String?
    public let defaultValue: String?
    public let allowedValues: [String]?
    public let pattern: String?
    public let minimum: Double?
    public let maximum: Double?
    public let minLength: Int?
    public let maxLength: Int?
    public let environmentSpecific: Bool
    public let secret: Bool
    
    public init(
        type: String,
        description: String? = nil,
        defaultValue: String? = nil,
        allowedValues: [String]? = nil,
        pattern: String? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        environmentSpecific: Bool = false,
        secret: Bool = false
    ) {
        self.type = type
        self.description = description
        self.defaultValue = defaultValue
        self.allowedValues = allowedValues
        self.pattern = pattern
        self.minimum = minimum
        self.maximum = maximum
        self.minLength = minLength
        self.maxLength = maxLength
        self.environmentSpecific = environmentSpecific
        self.secret = secret
    }
}