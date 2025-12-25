import Foundation
import SwiftUI

// MARK: - Form Container

@MainActor
@Observable
public final class FormContainer {
    public private(set) var fields: [any FormFieldProtocol] = []
    public private(set) var isValid = false
    public private(set) var isSubmitting = false
    public private(set) var isDirty = false
    public private(set) var errors: [ValidationError] = []
    public var focusedFieldId: String?

    private let onSubmit: () async throws -> Void
    private let validateOnChange: Bool
    private let validateOnBlur: Bool
    
    public init(
        fields: [any FormFieldProtocol],
        validateOnChange: Bool = false,
        validateOnBlur: Bool = true,
        onSubmit: @escaping () async throws -> Void = { }
    ) {
        self.fields = fields
        self.validateOnChange = validateOnChange
        self.validateOnBlur = validateOnBlur
        self.onSubmit = onSubmit
    }
    
    public func field<T: FormFieldProtocol>(withId id: String) -> T? {
        fields.first { $0.id == id } as? T
    }
    
    public func updateField<T>(id: String, value: T) {
        guard let index = fields.firstIndex(where: { $0.id == id }) else { return }
        
        if let field = fields[index] as? FormField<T> {
            field.value = value
            isDirty = true

            if validateOnChange {
                field.errors = field.validate()
            }

            updateValidationState()
        }
    }
    
    public func focusField(id: String?) {
        focusedFieldId = id
        
        for i in 0..<fields.count {
            fields[i].isFocused = fields[i].id == id
        }
        
        if id == nil && validateOnBlur {
            validateAllFields()
        }
    }
    
    public func focusNextField() {
        guard let currentId = focusedFieldId,
              let currentIndex = fields.firstIndex(where: { $0.id == currentId }) else {
            if let firstField = fields.first {
                focusField(id: firstField.id)
            }
            return
        }
        
        let nextIndex = currentIndex + 1
        if nextIndex < fields.count {
            focusField(id: fields[nextIndex].id)
        } else {
            focusField(id: nil)
        }
    }
    
    public func focusPreviousField() {
        guard let currentId = focusedFieldId,
              let currentIndex = fields.firstIndex(where: { $0.id == currentId }) else {
            return
        }
        
        let previousIndex = currentIndex - 1
        if previousIndex >= 0 {
            focusField(id: fields[previousIndex].id)
        }
    }
    
    public func validateField(id: String) -> Bool {
        guard let index = fields.firstIndex(where: { $0.id == id }) else { return false }
        
        fields[index].errors = fields[index].validate()
        updateValidationState()
        
        return fields[index].errors.isEmpty
    }
    
    public func validateAllFields() {
        errors = []
        
        for i in 0..<fields.count {
            let fieldErrors = fields[i].validate()
            fields[i].errors = fieldErrors
            errors.append(contentsOf: fieldErrors)
        }
        
        updateValidationState()
    }
    
    private func updateValidationState() {
        errors = fields.flatMap { $0.errors }
        isValid = errors.isEmpty && fields.allSatisfy { field in
            !field.isRequired || hasValue(field: field)
        }
    }
    
    private func hasValue(field: any FormFieldProtocol) -> Bool {
        if let stringField = field as? FormField<String> {
            return !stringField.value.isEmpty
        } else if let optionalField = field as? FormField<Any?> {
            return optionalField.value != nil
        }
        return true
    }
    
    public func submit() async throws {
        guard !isSubmitting else { return }
        
        isSubmitting = true
        defer { isSubmitting = false }
        
        validateAllFields()
        
        guard isValid else {
            if let firstErrorField = fields.first(where: { !$0.errors.isEmpty }) {
                focusField(id: firstErrorField.id)
            }
            throw FormError.validationFailed(errors)
        }
        
        try await onSubmit()
        isDirty = false
    }
    
    public func reset() {
        for i in 0..<fields.count {
            if let field = fields[i] as? FormField<Any> {
                field.reset()
            }
            fields[i].errors = []
        }
        
        errors = []
        isDirty = false
        isValid = false
        focusedFieldId = nil
    }
}

// MARK: - Form Error

public enum FormError: LocalizedError {
    case validationFailed([ValidationError])
    case submissionFailed(Error)
    case fieldNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .validationFailed(let errors):
            if errors.count == 1 {
                return errors[0].message
            } else {
                return "Please fix \(errors.count) errors"
            }
        case .submissionFailed(let error):
            return error.localizedDescription
        case .fieldNotFound(let id):
            return "Field with id '\(id)' not found"
        }
    }
}

// MARK: - Keyboard Toolbar

public struct KeyboardToolbar: ViewModifier {
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onDone: () -> Void
    let hasPrevious: Bool
    let hasNext: Bool
    
    public func body(content: Content) -> some View {
        #if os(iOS)
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    HStack {
                        Button(action: onPrevious) {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(!hasPrevious)

                        Button(action: onNext) {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(!hasNext)

                        Spacer()

                        Button("Done", action: onDone)
                            .fontWeight(.medium)
                    }
                }
            }
        #else
        content
        #endif
    }
}

// MARK: - Form Submission State

public enum FormSubmissionState {
    case idle
    case validating
    case submitting
    case success(String?)
    case failure(Error)
    
    public var isLoading: Bool {
        switch self {
        case .validating, .submitting:
            return true
        default:
            return false
        }
    }
    
    public var message: String? {
        switch self {
        case .success(let message):
            return message
        case .failure(let error):
            return error.localizedDescription
        default:
            return nil
        }
    }
}

// MARK: - Form Configuration

#if canImport(UIKit)
public enum KeyboardDismissMode: String, Sendable {
    case none
    case onDrag
    case interactive
}
#endif

public struct FormConfiguration: Sendable {
    public var spacing: CGFloat = 16
    public var labelWidth: CGFloat? = nil
    public var showRequiredIndicator = true
    public var requiredIndicator = "*"
    public var errorColor = Color.red
    public var focusColor = Color.accentColor
    public var disabledOpacity = 0.6
    public var animationDuration = 0.2
    #if canImport(UIKit)
    public var keyboardDismissMode = KeyboardDismissMode.interactive
    #endif
    
    public init() {}
    
    public static let `default` = FormConfiguration()
}

// MARK: - Form Style Protocol

public protocol FormStyle {
    associatedtype Body: View
    func makeBody(configuration: FormStyleConfiguration) -> Body
}

public struct FormStyleConfiguration {
    public let label: AnyView
    public let field: AnyView
    public let error: AnyView?
    public let helpText: AnyView?
    public let isRequired: Bool
    public let isFocused: Bool
    public let isDisabled: Bool
    public let hasError: Bool
}