import Foundation

// MARK: - Validation Error

public struct ValidationError: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let field: String
    public let message: String
    public let type: ValidationType

    public enum ValidationType: String, Sendable {
        case required
        case format
        case length
        case range
        case pattern
        case custom
    }
    
    public init(field: String, message: String, type: ValidationType = .custom) {
        self.field = field
        self.message = message
        self.type = type
    }
}

// MARK: - Validator Protocol

public protocol Validator<T>: Sendable {
    associatedtype T
    func validate(_ value: T, field: String) -> [ValidationError]
}

// MARK: - String Validators

public struct RequiredValidator: Validator {
    public init() {}

    public func validate(_ value: String, field: String) -> [ValidationError] {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [ValidationError(
                field: field,
                message: "\(field) is required",
                type: .required
            )]
        }
        return []
    }
}

public struct MinLengthValidator: Validator {
    public let minLength: Int
    
    public init(minLength: Int) {
        self.minLength = minLength
    }
    
    public func validate(_ value: String, field: String) -> [ValidationError] {
        if value.count < minLength {
            return [ValidationError(
                field: field,
                message: "\(field) must be at least \(minLength) characters",
                type: .length
            )]
        }
        return []
    }
}

public struct MaxLengthValidator: Validator {
    public let maxLength: Int
    
    public init(maxLength: Int) {
        self.maxLength = maxLength
    }
    
    public func validate(_ value: String, field: String) -> [ValidationError] {
        if value.count > maxLength {
            return [ValidationError(
                field: field,
                message: "\(field) must be at most \(maxLength) characters",
                type: .length
            )]
        }
        return []
    }
}

public struct RegexValidator: Validator {
    public let pattern: String
    public let message: String
    
    public init(pattern: String, message: String) {
        self.pattern = pattern
        self.message = message
    }
    
    public func validate(_ value: String, field: String) -> [ValidationError] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        
        let range = NSRange(location: 0, length: value.utf16.count)
        if regex.firstMatch(in: value, range: range) == nil {
            return [ValidationError(
                field: field,
                message: message,
                type: .pattern
            )]
        }
        return []
    }
}

public struct EmailValidator: Validator {
    private let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#

    public init() {}

    public func validate(_ value: String, field: String) -> [ValidationError] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(location: 0, length: value.utf16.count)
        if regex.firstMatch(in: value, range: range) == nil {
            return [ValidationError(
                field: field,
                message: "Please enter a valid email address",
                type: .format
            )]
        }
        return []
    }
}

public struct URLValidator: Validator {
    public init() {}
    
    public func validate(_ value: String, field: String) -> [ValidationError] {
        guard let url = URL(string: value),
              url.scheme != nil,
              url.host != nil else {
            return [ValidationError(
                field: field,
                message: "Please enter a valid URL",
                type: .format
            )]
        }
        return []
    }
}

public struct PhoneValidator: Validator {
    // Require at least 7 digits (minimum for valid phone numbers)
    private let pattern = #"^\+?[1-9]\d{6,14}$"#

    public init() {}

    public func validate(_ value: String, field: String) -> [ValidationError] {
        let cleaned = value.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        let validator = RegexValidator(
            pattern: pattern,
            message: "Please enter a valid phone number"
        )
        return validator.validate(cleaned, field: field)
    }
}

public struct PasswordValidator: Validator {
    public let requireUppercase: Bool
    public let requireLowercase: Bool
    public let requireNumbers: Bool
    public let requireSpecialChars: Bool
    
    public init(
        requireUppercase: Bool = true,
        requireLowercase: Bool = true,
        requireNumbers: Bool = true,
        requireSpecialChars: Bool = false
    ) {
        self.requireUppercase = requireUppercase
        self.requireLowercase = requireLowercase
        self.requireNumbers = requireNumbers
        self.requireSpecialChars = requireSpecialChars
    }
    
    public func validate(_ value: String, field: String) -> [ValidationError] {
        var errors: [ValidationError] = []
        
        if requireUppercase && !value.contains(where: { $0.isUppercase }) {
            errors.append(ValidationError(
                field: field,
                message: "Password must contain at least one uppercase letter",
                type: .format
            ))
        }
        
        if requireLowercase && !value.contains(where: { $0.isLowercase }) {
            errors.append(ValidationError(
                field: field,
                message: "Password must contain at least one lowercase letter",
                type: .format
            ))
        }
        
        if requireNumbers && !value.contains(where: { $0.isNumber }) {
            errors.append(ValidationError(
                field: field,
                message: "Password must contain at least one number",
                type: .format
            ))
        }
        
        if requireSpecialChars {
            let specialChars = CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:,.<>?")
            if value.rangeOfCharacter(from: specialChars) == nil {
                errors.append(ValidationError(
                    field: field,
                    message: "Password must contain at least one special character",
                    type: .format
                ))
            }
        }
        
        return errors
    }
}

// MARK: - Number Validators

public struct RangeValidator<T: Comparable & Sendable>: Validator {
    public let range: ClosedRange<T>

    public init(range: ClosedRange<T>) {
        self.range = range
    }

    public func validate(_ value: T?, field: String) -> [ValidationError] {
        guard let value = value else { return [] }

        if !range.contains(value) {
            return [ValidationError(
                field: field,
                message: "\(field) must be between \(range.lowerBound) and \(range.upperBound)",
                type: .range
            )]
        }
        return []
    }
}

// MARK: - Date Validators

public struct DateRangeValidator: Validator {
    public let range: ClosedRange<Date>
    
    public init(range: ClosedRange<Date>) {
        self.range = range
    }
    
    public func validate(_ value: Date?, field: String) -> [ValidationError] {
        guard let value = value else { return [] }
        
        if !range.contains(value) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            
            return [ValidationError(
                field: field,
                message: "\(field) must be between \(formatter.string(from: range.lowerBound)) and \(formatter.string(from: range.upperBound))",
                type: .range
            )]
        }
        return []
    }
}

public struct FutureDateValidator: Validator {
    public init() {}
    
    public func validate(_ value: Date?, field: String) -> [ValidationError] {
        guard let value = value else { return [] }
        
        if value <= Date() {
            return [ValidationError(
                field: field,
                message: "\(field) must be in the future",
                type: .range
            )]
        }
        return []
    }
}

public struct PastDateValidator: Validator {
    public init() {}
    
    public func validate(_ value: Date?, field: String) -> [ValidationError] {
        guard let value = value else { return [] }
        
        if value >= Date() {
            return [ValidationError(
                field: field,
                message: "\(field) must be in the past",
                type: .range
            )]
        }
        return []
    }
}

// MARK: - Custom Validators

public struct CustomValidator<T: Sendable>: Validator {
    private let validation: @Sendable (T, String) -> [ValidationError]

    public init(validation: @escaping @Sendable (T, String) -> [ValidationError]) {
        self.validation = validation
    }

    public func validate(_ value: T, field: String) -> [ValidationError] {
        validation(value, field)
    }
}

public struct ComparisonValidator<T: Comparable & Sendable>: Validator {
    public enum ComparisonType: Sendable {
        case equal
        case notEqual
        case greaterThan
        case greaterThanOrEqual
        case lessThan
        case lessThanOrEqual
    }

    private let otherValue: @Sendable () -> T
    private let comparison: ComparisonType
    private let message: String

    public init(
        otherValue: @escaping @Sendable () -> T,
        comparison: ComparisonType,
        message: String
    ) {
        self.otherValue = otherValue
        self.comparison = comparison
        self.message = message
    }
    
    public func validate(_ value: T, field: String) -> [ValidationError] {
        let other = otherValue()
        
        let isValid: Bool
        switch comparison {
        case .equal:
            isValid = value == other
        case .notEqual:
            isValid = value != other
        case .greaterThan:
            isValid = value > other
        case .greaterThanOrEqual:
            isValid = value >= other
        case .lessThan:
            isValid = value < other
        case .lessThanOrEqual:
            isValid = value <= other
        }
        
        if !isValid {
            return [ValidationError(
                field: field,
                message: message,
                type: .custom
            )]
        }
        return []
    }
}

// MARK: - Composite Validators

public struct CompositeValidator<T>: Validator {
    private let validators: [any Validator<T>]
    
    public init(validators: [any Validator<T>]) {
        self.validators = validators
    }
    
    public func validate(_ value: T, field: String) -> [ValidationError] {
        validators.flatMap { $0.validate(value, field: field) }
    }
}

public struct ConditionalValidator<T: Sendable>: Validator {
    private let condition: @Sendable (T) -> Bool
    private let validator: any Validator<T>

    public init(
        condition: @escaping @Sendable (T) -> Bool,
        validator: any Validator<T>
    ) {
        self.condition = condition
        self.validator = validator
    }

    public func validate(_ value: T, field: String) -> [ValidationError] {
        if condition(value) {
            return validator.validate(value, field: field)
        }
        return []
    }
}