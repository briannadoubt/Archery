import Foundation
import SwiftUI

// MARK: - Preview Seeds

public struct FormPreviewSeeds {
    
    // MARK: - Valid Seeds
    
    @MainActor
    @MainActor
    public static func validLoginForm() -> FormContainer {
        let fields: [any FormFieldProtocol] = [
            EmailField(
                id: "email",
                label: "Email",
                value: "user@example.com",
                isRequired: true
            ),
            PasswordField(
                id: "password",
                label: "Password",
                value: "SecureP@ssw0rd123",
                isRequired: true
            )
        ]
        
        return FormContainer(fields: fields)
    }
    
    @MainActor
    public static func validRegistrationForm() -> FormContainer {
        let fields: [any FormFieldProtocol] = [
            TextField(
                id: "firstName",
                label: "First Name",
                value: "John",
                isRequired: true
            ),
            TextField(
                id: "lastName",
                label: "Last Name",
                value: "Doe",
                isRequired: true
            ),
            EmailField(
                id: "email",
                label: "Email",
                value: "john.doe@example.com",
                isRequired: true
            ),
            PasswordField(
                id: "password",
                label: "Password",
                value: "SecureP@ssw0rd123",
                isRequired: true,
                minLength: 8
            ),
            PasswordField(
                id: "confirmPassword",
                label: "Confirm Password",
                value: "SecureP@ssw0rd123",
                isRequired: true
            ),
            BooleanField(
                id: "terms",
                label: "I agree to the Terms and Conditions",
                value: true
            )
        ]
        
        return FormContainer(fields: fields)
    }
    
    // MARK: - Invalid Seeds
    
    @MainActor
    public static func invalidEmailForm() -> FormContainer {
        let emailField = EmailField(
            id: "email",
            label: "Email",
            value: "invalid-email",
            isRequired: true
        )
        emailField.errors = [
            ValidationError(
                field: "Email",
                message: "Please enter a valid email address",
                type: .format
            )
        ]
        
        return FormContainer(fields: [emailField])
    }
    
    @MainActor
    public static func passwordMismatchForm() -> FormContainer {
        let passwordField = PasswordField(
            id: "password",
            label: "Password",
            value: "Password123",
            isRequired: true
        )
        
        let confirmPasswordField = PasswordField(
            id: "confirmPassword",
            label: "Confirm Password",
            value: "Password456",
            isRequired: true
        )
        confirmPasswordField.errors = [
            ValidationError(
                field: "Confirm Password",
                message: "Passwords do not match",
                type: .custom
            )
        ]
        
        return FormContainer(fields: [passwordField, confirmPasswordField])
    }
    
    @MainActor
    public static func allFieldTypesForm() -> FormContainer {
        let fields: [any FormFieldProtocol] = [
            TextField(
                id: "text",
                label: "Text Field",
                value: "Sample text",
                placeholder: "Enter text",
                helpText: "This is a regular text field"
            ),
            EmailField(
                id: "email",
                label: "Email Field",
                value: "",
                placeholder: "your@email.com",
                isRequired: true
            ),
            PasswordField(
                id: "password",
                label: "Password Field",
                value: "",
                placeholder: "Enter secure password",
                isRequired: true
            ),
            NumberField(
                id: "age",
                label: "Age",
                value: 25,
                placeholder: "Enter your age",
                range: 0...120
            ),
            DateField(
                id: "birthDate",
                label: "Birth Date",
                value: Date(),
                displayedComponents: [.date]
            ),
            BooleanField(
                id: "subscribe",
                label: "Subscribe to newsletter",
                value: false
            ),
            TextAreaField(
                id: "bio",
                label: "Biography",
                value: "",
                placeholder: "Tell us about yourself",
                maxLength: 500
            )
        ]
        
        return FormContainer(fields: fields)
    }
    
    // MARK: - Edge Cases
    
    @MainActor
    public static func emptyRequiredFieldsForm() -> FormContainer {
        let firstNameField = TextField(
            id: "firstName",
            label: "First Name",
            value: "",
            isRequired: true
        )
        firstNameField.errors = [
            ValidationError(
                field: "First Name",
                message: "First Name is required",
                type: .required
            )
        ]
        
        let lastNameField = TextField(
            id: "lastName",
            label: "Last Name",
            value: "",
            isRequired: true
        )
        lastNameField.errors = [
            ValidationError(
                field: "Last Name",
                message: "Last Name is required",
                type: .required
            )
        ]
        
        let emailField = EmailField(
            id: "email",
            label: "Email",
            value: "",
            isRequired: true
        )
        emailField.errors = [
            ValidationError(
                field: "Email",
                message: "Email is required",
                type: .required
            )
        ]
        
        return FormContainer(fields: [firstNameField, lastNameField, emailField])
    }
    
    @MainActor
    public static func longTextForm() -> FormContainer {
        let loremIpsum = """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
        """
        
        let fields: [any FormFieldProtocol] = [
            TextAreaField(
                id: "description",
                label: "Description",
                value: loremIpsum,
                maxLength: 1000,
                minLines: 5
            ),
            TextAreaField(
                id: "notes",
                label: "Additional Notes",
                value: loremIpsum + "\n\n" + loremIpsum,
                maxLength: 2000,
                minLines: 10
            )
        ]
        
        return FormContainer(fields: fields)
    }
    
    @MainActor
    public static func disabledFieldsForm() -> FormContainer {
        let emailField = EmailField(
            id: "email",
            label: "Email (Disabled)",
            value: "locked@example.com",
            isRequired: true
        )
        emailField.isEnabled = false
        
        let passwordField = PasswordField(
            id: "password",
            label: "Password (Disabled)",
            value: "LockedPassword",
            isRequired: true
        )
        passwordField.isEnabled = false
        
        let activeField = TextField(
            id: "active",
            label: "Active Field",
            value: "",
            placeholder: "You can edit this"
        )
        
        return FormContainer(fields: [emailField, passwordField, activeField])
    }
    
    @MainActor
    public static func multipleErrorsForm() -> FormContainer {
        let passwordField = PasswordField(
            id: "password",
            label: "Password",
            value: "weak",
            isRequired: true,
            minLength: 8,
            requireUppercase: true,
            requireNumbers: true
        )
        passwordField.errors = [
            ValidationError(
                field: "Password",
                message: "Password must be at least 8 characters",
                type: .length
            ),
            ValidationError(
                field: "Password",
                message: "Password must contain at least one uppercase letter",
                type: .format
            ),
            ValidationError(
                field: "Password",
                message: "Password must contain at least one number",
                type: .format
            )
        ]
        
        let emailField = EmailField(
            id: "email",
            label: "Email",
            value: "@invalid",
            isRequired: true
        )
        emailField.errors = [
            ValidationError(
                field: "Email",
                message: "Please enter a valid email address",
                type: .format
            )
        ]
        
        return FormContainer(fields: [emailField, passwordField])
    }
    
    // MARK: - Loading States
    
    @MainActor
    public static func submittingForm() -> FormContainer {
        let container = validLoginForm()
        container.isSubmitting = true
        return container
    }
    
    @MainActor
    public static func dirtyForm() -> FormContainer {
        let container = validRegistrationForm()
        container.isDirty = true
        return container
    }
}

// MARK: - Preview Helpers

public extension FormContainer {
    static var preview: FormContainer {
        FormPreviewSeeds.validRegistrationForm()
    }
    
    static var previewWithErrors: FormContainer {
        FormPreviewSeeds.multipleErrorsForm()
    }
    
    static var previewEmpty: FormContainer {
        FormPreviewSeeds.emptyRequiredFieldsForm()
    }
    
    static var previewAllTypes: FormContainer {
        FormPreviewSeeds.allFieldTypesForm()
    }
}

// MARK: - SwiftUI Preview Provider

#if DEBUG
struct FormPreviewProvider: PreviewProvider {
    static var previews: some View {
        Group {
            FormView(container: .preview) {
                ForEach(FormContainer.preview.fields, id: \.id) { field in
                    FormFieldView(field: field)
                }
            }
            .previewDisplayName("Valid Form")
            
            FormView(container: .previewWithErrors) {
                ForEach(FormContainer.previewWithErrors.fields, id: \.id) { field in
                    FormFieldView(field: field)
                }
            }
            .previewDisplayName("Form with Errors")
            
            FormView(container: .previewEmpty) {
                ForEach(FormContainer.previewEmpty.fields, id: \.id) { field in
                    FormFieldView(field: field)
                }
            }
            .previewDisplayName("Empty Required Fields")
            
            FormView(container: .previewAllTypes) {
                ForEach(FormContainer.previewAllTypes.fields, id: \.id) { field in
                    FormFieldView(field: field)
                }
            }
            .previewDisplayName("All Field Types")
        }
    }
}
#endif