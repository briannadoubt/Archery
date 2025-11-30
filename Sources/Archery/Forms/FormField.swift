import Foundation
import SwiftUI
import Combine

// MARK: - Field Protocol

public protocol FormFieldProtocol: Identifiable {
    associatedtype Value
    
    var id: String { get }
    var label: String { get }
    var value: Value { get set }
    var placeholder: String? { get }
    var helpText: String? { get }
    var isRequired: Bool { get }
    var isEnabled: Bool { get set }
    var isFocused: Bool { get set }
    var errors: [ValidationError] { get set }
    var validators: [any Validator<Value>] { get }
    
    func validate() -> [ValidationError]
}

// MARK: - Form Field Implementation

@MainActor
@Observable
public class FormField<T>: FormFieldProtocol, Identifiable {
    public let id: String
    public let label: String
    public var value: T
    public let placeholder: String?
    public let helpText: String?
    public let isRequired: Bool
    public var isEnabled: Bool = true
    public var isFocused: Bool = false
    public var errors: [ValidationError] = []
    public let validators: [any Validator<T>]
    
    private let defaultValue: T
    private var cancellables = Set<AnyCancellable>()
    
    public init(
        id: String,
        label: String,
        value: T,
        placeholder: String? = nil,
        helpText: String? = nil,
        isRequired: Bool = false,
        validators: [any Validator<T>] = []
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.defaultValue = value
        self.placeholder = placeholder
        self.helpText = helpText
        self.isRequired = isRequired
        self.validators = validators
    }
    
    public func validate() -> [ValidationError] {
        errors = validators.flatMap { validator in
            validator.validate(value, field: label)
        }
        
        if isRequired {
            if let stringValue = value as? String, stringValue.isEmpty {
                errors.append(ValidationError(
                    field: label,
                    message: "\(label) is required",
                    type: .required
                ))
            } else if let optionalValue = value as? Any?, optionalValue == nil {
                errors.append(ValidationError(
                    field: label,
                    message: "\(label) is required",
                    type: .required
                ))
            }
        }
        
        return errors
    }
    
    public func reset() {
        value = defaultValue
        errors = []
        isFocused = false
    }
    
    public var hasErrors: Bool {
        !errors.isEmpty
    }
    
    public var errorMessage: String? {
        errors.first?.message
    }
}

// MARK: - Specialized Field Types

public final class TextField: FormField<String> {
    public let keyboardType: UIKeyboardType
    public let textContentType: UITextContentType?
    public let autocapitalization: TextInputAutocapitalization
    public let autocorrectionDisabled: Bool
    
    public init(
        id: String,
        label: String,
        value: String = "",
        placeholder: String? = nil,
        helpText: String? = nil,
        isRequired: Bool = false,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        autocapitalization: TextInputAutocapitalization = .sentences,
        autocorrectionDisabled: Bool = false,
        validators: [any Validator<String>] = []
    ) {
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.autocapitalization = autocapitalization
        self.autocorrectionDisabled = autocorrectionDisabled
        
        super.init(
            id: id,
            label: label,
            value: value,
            placeholder: placeholder,
            helpText: helpText,
            isRequired: isRequired,
            validators: validators
        )
    }
}

public final class EmailField: TextField {
    public init(
        id: String = "email",
        label: String = "Email",
        value: String = "",
        placeholder: String? = "Enter your email",
        isRequired: Bool = true
    ) {
        super.init(
            id: id,
            label: label,
            value: value,
            placeholder: placeholder,
            isRequired: isRequired,
            keyboardType: .emailAddress,
            textContentType: .emailAddress,
            autocapitalization: .never,
            autocorrectionDisabled: true,
            validators: [EmailValidator()]
        )
    }
}

public final class PasswordField: TextField {
    public let minLength: Int
    public let requireUppercase: Bool
    public let requireLowercase: Bool
    public let requireNumbers: Bool
    public let requireSpecialChars: Bool
    
    public init(
        id: String = "password",
        label: String = "Password",
        value: String = "",
        placeholder: String? = "Enter password",
        isRequired: Bool = true,
        minLength: Int = 8,
        requireUppercase: Bool = true,
        requireLowercase: Bool = true,
        requireNumbers: Bool = true,
        requireSpecialChars: Bool = false
    ) {
        self.minLength = minLength
        self.requireUppercase = requireUppercase
        self.requireLowercase = requireLowercase
        self.requireNumbers = requireNumbers
        self.requireSpecialChars = requireSpecialChars
        
        var validators: [any Validator<String>] = [
            MinLengthValidator(minLength: minLength)
        ]
        
        if requireUppercase || requireLowercase || requireNumbers || requireSpecialChars {
            validators.append(PasswordValidator(
                requireUppercase: requireUppercase,
                requireLowercase: requireLowercase,
                requireNumbers: requireNumbers,
                requireSpecialChars: requireSpecialChars
            ))
        }
        
        super.init(
            id: id,
            label: label,
            value: value,
            placeholder: placeholder,
            isRequired: isRequired,
            keyboardType: .default,
            textContentType: .password,
            autocapitalization: .never,
            autocorrectionDisabled: true,
            validators: validators
        )
    }
}

public final class NumberField: FormField<Double?> {
    public let range: ClosedRange<Double>?
    public let step: Double
    public let formatter: NumberFormatter
    
    public init(
        id: String,
        label: String,
        value: Double? = nil,
        placeholder: String? = nil,
        helpText: String? = nil,
        isRequired: Bool = false,
        range: ClosedRange<Double>? = nil,
        step: Double = 1.0,
        formatter: NumberFormatter? = nil,
        validators: [any Validator<Double?>] = []
    ) {
        self.range = range
        self.step = step
        self.formatter = formatter ?? {
            let fmt = NumberFormatter()
            fmt.numberStyle = .decimal
            return fmt
        }()
        
        var allValidators = validators
        if let range = range {
            allValidators.append(RangeValidator(range: range))
        }
        
        super.init(
            id: id,
            label: label,
            value: value,
            placeholder: placeholder,
            helpText: helpText,
            isRequired: isRequired,
            validators: allValidators
        )
    }
}

public final class DateField: FormField<Date?> {
    public let dateRange: ClosedRange<Date>?
    public let displayedComponents: DatePickerComponents
    
    public init(
        id: String,
        label: String,
        value: Date? = nil,
        placeholder: String? = nil,
        helpText: String? = nil,
        isRequired: Bool = false,
        dateRange: ClosedRange<Date>? = nil,
        displayedComponents: DatePickerComponents = [.date, .hourAndMinute],
        validators: [any Validator<Date?>] = []
    ) {
        self.dateRange = dateRange
        self.displayedComponents = displayedComponents
        
        var allValidators = validators
        if let dateRange = dateRange {
            allValidators.append(DateRangeValidator(range: dateRange))
        }
        
        super.init(
            id: id,
            label: label,
            value: value,
            placeholder: placeholder,
            helpText: helpText,
            isRequired: isRequired,
            validators: allValidators
        )
    }
}

public final class BooleanField: FormField<Bool> {
    public init(
        id: String,
        label: String,
        value: Bool = false,
        helpText: String? = nil
    ) {
        super.init(
            id: id,
            label: label,
            value: value,
            helpText: helpText,
            isRequired: false,
            validators: []
        )
    }
}

public final class SelectField<T: Hashable>: FormField<T?> {
    public let options: [SelectOption<T>]
    public let allowMultiple: Bool
    
    public struct SelectOption<T: Hashable>: Identifiable {
        public let id = UUID()
        public let value: T
        public let label: String
        public let icon: String?
        
        public init(value: T, label: String, icon: String? = nil) {
            self.value = value
            self.label = label
            self.icon = icon
        }
    }
    
    public init(
        id: String,
        label: String,
        value: T? = nil,
        options: [SelectOption<T>],
        placeholder: String? = "Select an option",
        helpText: String? = nil,
        isRequired: Bool = false,
        allowMultiple: Bool = false,
        validators: [any Validator<T?>] = []
    ) {
        self.options = options
        self.allowMultiple = allowMultiple
        
        super.init(
            id: id,
            label: label,
            value: value,
            placeholder: placeholder,
            helpText: helpText,
            isRequired: isRequired,
            validators: validators
        )
    }
}

public final class TextAreaField: FormField<String> {
    public let maxLength: Int?
    public let minLines: Int
    public let maxLines: Int?
    
    public init(
        id: String,
        label: String,
        value: String = "",
        placeholder: String? = nil,
        helpText: String? = nil,
        isRequired: Bool = false,
        maxLength: Int? = nil,
        minLines: Int = 3,
        maxLines: Int? = nil,
        validators: [any Validator<String>] = []
    ) {
        self.maxLength = maxLength
        self.minLines = minLines
        self.maxLines = maxLines
        
        var allValidators = validators
        if let maxLength = maxLength {
            allValidators.append(MaxLengthValidator(maxLength: maxLength))
        }
        
        super.init(
            id: id,
            label: label,
            value: value,
            placeholder: placeholder,
            helpText: helpText,
            isRequired: isRequired,
            validators: allValidators
        )
    }
}