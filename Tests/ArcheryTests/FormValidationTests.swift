import XCTest
@testable import Archery

final class FormValidationTests: XCTestCase {
    
    // MARK: - String Validators
    
    func testRequiredValidator() {
        let validator = RequiredValidator()
        
        XCTAssertFalse(validator.validate("", field: "Test").isEmpty)
        XCTAssertFalse(validator.validate("  ", field: "Test").isEmpty)
        XCTAssertTrue(validator.validate("valid", field: "Test").isEmpty)
    }
    
    func testMinLengthValidator() {
        let validator = MinLengthValidator(minLength: 5)
        
        XCTAssertFalse(validator.validate("1234", field: "Test").isEmpty)
        XCTAssertTrue(validator.validate("12345", field: "Test").isEmpty)
        XCTAssertTrue(validator.validate("123456", field: "Test").isEmpty)
    }
    
    func testMaxLengthValidator() {
        let validator = MaxLengthValidator(maxLength: 10)
        
        XCTAssertTrue(validator.validate("123456789", field: "Test").isEmpty)
        XCTAssertTrue(validator.validate("1234567890", field: "Test").isEmpty)
        XCTAssertFalse(validator.validate("12345678901", field: "Test").isEmpty)
    }
    
    func testEmailValidator() {
        let validator = EmailValidator()
        
        XCTAssertTrue(validator.validate("user@example.com", field: "Email").isEmpty)
        XCTAssertTrue(validator.validate("user.name@example.co.uk", field: "Email").isEmpty)
        XCTAssertFalse(validator.validate("invalid", field: "Email").isEmpty)
        XCTAssertFalse(validator.validate("@example.com", field: "Email").isEmpty)
        XCTAssertFalse(validator.validate("user@", field: "Email").isEmpty)
    }
    
    func testURLValidator() {
        let validator = URLValidator()
        
        XCTAssertTrue(validator.validate("https://example.com", field: "URL").isEmpty)
        XCTAssertTrue(validator.validate("http://subdomain.example.com/path", field: "URL").isEmpty)
        XCTAssertFalse(validator.validate("invalid-url", field: "URL").isEmpty)
        XCTAssertFalse(validator.validate("example.com", field: "URL").isEmpty)
    }
    
    func testPhoneValidator() {
        let validator = PhoneValidator()
        
        XCTAssertTrue(validator.validate("+14155551234", field: "Phone").isEmpty)
        XCTAssertTrue(validator.validate("4155551234", field: "Phone").isEmpty)
        XCTAssertFalse(validator.validate("123", field: "Phone").isEmpty)
        XCTAssertFalse(validator.validate("abc", field: "Phone").isEmpty)
    }
    
    func testPasswordValidator() {
        let validator = PasswordValidator(
            requireUppercase: true,
            requireLowercase: true,
            requireNumbers: true,
            requireSpecialChars: true
        )
        
        XCTAssertTrue(validator.validate("SecureP@ss1", field: "Password").isEmpty)
        XCTAssertFalse(validator.validate("password", field: "Password").isEmpty)
        XCTAssertFalse(validator.validate("PASSWORD", field: "Password").isEmpty)
        XCTAssertFalse(validator.validate("Password", field: "Password").isEmpty)
        XCTAssertFalse(validator.validate("Password1", field: "Password").isEmpty)
    }
    
    // MARK: - Number Validators
    
    func testRangeValidator() {
        let validator = RangeValidator(range: 0.0...100.0)
        
        XCTAssertTrue(validator.validate(0.0, field: "Number").isEmpty)
        XCTAssertTrue(validator.validate(50.0, field: "Number").isEmpty)
        XCTAssertTrue(validator.validate(100.0, field: "Number").isEmpty)
        XCTAssertFalse(validator.validate(-1.0, field: "Number").isEmpty)
        XCTAssertFalse(validator.validate(101.0, field: "Number").isEmpty)
    }
    
    // MARK: - Date Validators
    
    func testFutureDateValidator() {
        let validator = FutureDateValidator()
        
        let futureDate = Date().addingTimeInterval(86400) // Tomorrow
        let pastDate = Date().addingTimeInterval(-86400) // Yesterday
        
        XCTAssertTrue(validator.validate(futureDate, field: "Date").isEmpty)
        XCTAssertFalse(validator.validate(pastDate, field: "Date").isEmpty)
        XCTAssertFalse(validator.validate(Date(), field: "Date").isEmpty)
    }
    
    func testPastDateValidator() {
        let validator = PastDateValidator()

        let futureDate = Date().addingTimeInterval(86400) // Tomorrow
        let pastDate = Date().addingTimeInterval(-86400) // Yesterday
        let nowDate = Date().addingTimeInterval(1) // 1 second in future to avoid timing issues

        XCTAssertFalse(validator.validate(futureDate, field: "Date").isEmpty)
        XCTAssertTrue(validator.validate(pastDate, field: "Date").isEmpty)
        XCTAssertFalse(validator.validate(nowDate, field: "Date").isEmpty)
    }
}

final class FormFieldTests: XCTestCase {
    
    @MainActor
    func testTextFieldInitialization() {
        let field = TextField(
            id: "test",
            label: "Test Field",
            value: "initial",
            placeholder: "Enter value",
            helpText: "Help text",
            isRequired: true
        )
        
        XCTAssertEqual(field.id, "test")
        XCTAssertEqual(field.label, "Test Field")
        XCTAssertEqual(field.value, "initial")
        XCTAssertEqual(field.placeholder, "Enter value")
        XCTAssertEqual(field.helpText, "Help text")
        XCTAssertTrue(field.isRequired)
    }
    
    @MainActor
    func testFieldValidation() {
        let field = EmailField(
            id: "email",
            label: "Email",
            value: "invalid",
            isRequired: true
        )
        
        let errors = field.validate()
        XCTAssertFalse(errors.isEmpty)
        XCTAssertEqual(errors.first?.type, .format)
    }
    
    @MainActor
    func testFieldReset() {
        let field = TextField(
            id: "test",
            label: "Test",
            value: "initial"
        )
        
        field.value = "changed"
        field.errors = [ValidationError(field: "Test", message: "Error", type: .custom)]
        
        field.reset()
        
        XCTAssertEqual(field.value, "initial")
        XCTAssertTrue(field.errors.isEmpty)
    }
    
    @MainActor
    func testNumberFieldWithRange() {
        let field = NumberField(
            id: "age",
            label: "Age",
            value: 150,
            range: 0...120
        )
        
        let errors = field.validate()
        XCTAssertFalse(errors.isEmpty)
        XCTAssertEqual(errors.first?.type, .range)
    }
    
    @MainActor
    func testPasswordFieldRequirements() {
        let field = PasswordField(
            id: "password",
            label: "Password",
            value: "weak",
            minLength: 8,
            requireUppercase: true,
            requireNumbers: true
        )
        
        let errors = field.validate()
        XCTAssertGreaterThan(errors.count, 1)
    }
}

final class FormContainerTests: XCTestCase {
    
    @MainActor
    func testFormContainerInitialization() {
        let fields: [any FormFieldProtocol] = [
            TextField(id: "field1", label: "Field 1", value: ""),
            TextField(id: "field2", label: "Field 2", value: "")
        ]
        
        let container = FormContainer(fields: fields)
        
        XCTAssertEqual(container.fields.count, 2)
        XCTAssertFalse(container.isValid)
        XCTAssertFalse(container.isSubmitting)
        XCTAssertFalse(container.isDirty)
    }
    
    @MainActor
    func testFieldUpdate() {
        let field = TextField(id: "test", label: "Test", value: "")
        let container = FormContainer(fields: [field])
        
        container.updateField(id: "test", value: "new value")
        
        XCTAssertTrue(container.isDirty)
        if let updatedField: TextField = container.field(withId: "test") {
            XCTAssertEqual(updatedField.value, "new value")
        } else {
            XCTFail("Field not found or wrong type")
        }
    }
    
    @MainActor
    func testFocusManagement() {
        let fields: [any FormFieldProtocol] = [
            TextField(id: "field1", label: "Field 1", value: ""),
            TextField(id: "field2", label: "Field 2", value: ""),
            TextField(id: "field3", label: "Field 3", value: "")
        ]
        
        let container = FormContainer(fields: fields)
        
        container.focusField(id: "field1")
        XCTAssertEqual(container.focusedFieldId, "field1")
        
        container.focusNextField()
        XCTAssertEqual(container.focusedFieldId, "field2")
        
        container.focusNextField()
        XCTAssertEqual(container.focusedFieldId, "field3")
        
        container.focusPreviousField()
        XCTAssertEqual(container.focusedFieldId, "field2")
    }
    
    @MainActor
    func testFormValidation() {
        let emailField = EmailField(
            id: "email",
            label: "Email",
            value: "invalid",
            isRequired: true
        )
        
        let passwordField = PasswordField(
            id: "password",
            label: "Password",
            value: "",
            isRequired: true
        )
        
        let container = FormContainer(fields: [emailField, passwordField])
        
        container.validateAllFields()
        
        XCTAssertFalse(container.isValid)
        XCTAssertGreaterThan(container.errors.count, 0)
    }
    
    @MainActor
    func testFormSubmission() async {
        var submitCalled = false
        
        let field = TextField(
            id: "test",
            label: "Test",
            value: "valid"
        )
        
        let container = FormContainer(
            fields: [field],
            onSubmit: {
                submitCalled = true
            }
        )
        
        do {
            try await container.submit()
            XCTAssertTrue(submitCalled)
        } catch {
            XCTFail("Submit should not throw for valid form")
        }
    }
    
    @MainActor
    func testFormReset() {
        let field = TextField(
            id: "test",
            label: "Test",
            value: "initial"
        )
        
        let container = FormContainer(fields: [field])
        
        container.updateField(id: "test", value: "changed")
        container.validateAllFields()
        
        container.reset()
        
        XCTAssertFalse(container.isDirty)
        XCTAssertTrue(container.errors.isEmpty)
    }
}

final class FormPreviewSeedsTests: XCTestCase {
    
    @MainActor
    func testValidLoginForm() {
        let container = FormPreviewSeeds.validLoginForm()
        
        XCTAssertEqual(container.fields.count, 2)
        container.validateAllFields()
        XCTAssertTrue(container.isValid)
    }
    
    @MainActor
    func testInvalidEmailForm() {
        let container = FormPreviewSeeds.invalidEmailForm()
        
        XCTAssertEqual(container.fields.count, 1)
        XCTAssertFalse(container.fields[0].errors.isEmpty)
    }
    
    @MainActor
    func testAllFieldTypesForm() {
        let container = FormPreviewSeeds.allFieldTypesForm()
        
        XCTAssertEqual(container.fields.count, 7)
        
        let fieldTypes = container.fields.map { type(of: $0) }
        XCTAssertTrue(fieldTypes.contains { $0 == TextField.self })
        XCTAssertTrue(fieldTypes.contains { $0 == EmailField.self })
        XCTAssertTrue(fieldTypes.contains { $0 == PasswordField.self })
        XCTAssertTrue(fieldTypes.contains { $0 == NumberField.self })
        XCTAssertTrue(fieldTypes.contains { $0 == DateField.self })
        XCTAssertTrue(fieldTypes.contains { $0 == BooleanField.self })
        XCTAssertTrue(fieldTypes.contains { $0 == TextAreaField.self })
    }
    
    @MainActor
    func testEmptyRequiredFieldsForm() {
        let container = FormPreviewSeeds.emptyRequiredFieldsForm()
        
        container.fields.forEach { field in
            XCTAssertFalse(field.errors.isEmpty)
            XCTAssertEqual(field.errors.first?.type, .required)
        }
    }
    
    @MainActor
    func testMultipleErrorsForm() {
        let container = FormPreviewSeeds.multipleErrorsForm()
        
        let totalErrors = container.fields.flatMap { $0.errors }
        XCTAssertGreaterThan(totalErrors.count, 2)
    }
}