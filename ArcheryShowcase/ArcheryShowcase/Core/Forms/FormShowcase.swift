import Foundation
import SwiftUI
import Archery

// MARK: - Form Showcase
//
// Demonstrates Archery's form validation system:
// - FormContainer for state management
// - Typed field classes (TextField, EmailField, PasswordField, NumberField, DateField)
// - Validators (Required, Email, MinLength, MaxLength, Range, etc.)
// - Real-time validation feedback

// MARK: - Task Form

@MainActor
final class TaskFormModel: ObservableObject {
    @Published var container: FormContainer

    // Field references for binding
    let titleField: Archery.TextField
    let descriptionField: TextAreaField
    let priorityField: SelectField<String>
    let dueDateField: DateField
    let assigneeEmailField: Archery.TextField
    let estimatedHoursField: NumberField

    init() {
        // Create fields with validation
        titleField = Archery.TextField(
            id: "title",
            label: "Task Title",
            placeholder: "What needs to be done?",
            isRequired: true,
            validators: [
                MinLengthValidator(minLength: 3),
                MaxLengthValidator(maxLength: 100)
            ]
        )

        descriptionField = TextAreaField(
            id: "description",
            label: "Description",
            placeholder: "Add more details about this task...",
            helpText: "Optional but recommended",
            maxLength: 500,
            minLines: 3,
            maxLines: 6
        )

        priorityField = SelectField<String>(
            id: "priority",
            label: "Priority",
            value: "medium",
            options: [
                .init(value: "low", label: "Low", icon: "arrow.down"),
                .init(value: "medium", label: "Medium", icon: "minus"),
                .init(value: "high", label: "High", icon: "arrow.up"),
                .init(value: "urgent", label: "Urgent", icon: "exclamationmark.2")
            ],
            isRequired: true
        )

        dueDateField = DateField(
            id: "dueDate",
            label: "Due Date",
            placeholder: "Select a due date",
            helpText: "When should this be completed?",
            dateRange: Date()...Date().addingTimeInterval(365 * 24 * 60 * 60)
        )

        assigneeEmailField = Archery.TextField(
            id: "assigneeEmail",
            label: "Assignee Email",
            placeholder: "team@example.com",
            helpText: "Optional: assign to a team member",
            validators: [EmailValidator()]
        )

        estimatedHoursField = NumberField(
            id: "estimatedHours",
            label: "Estimated Hours",
            placeholder: "e.g., 4",
            helpText: "How long will this take?",
            range: 0.5...100,
            step: 0.5
        )

        // Create container with all fields
        container = FormContainer(
            fields: [
                titleField,
                descriptionField,
                priorityField,
                dueDateField,
                assigneeEmailField,
                estimatedHoursField
            ]
        )
    }

    func validate() -> Bool {
        container.validateAllFields()
        return container.isValid
    }

    func reset() {
        container.reset()
    }

    var taskData: (title: String, description: String, priority: String, dueDate: Date?, assigneeEmail: String?, estimatedHours: Double?) {
        (
            title: titleField.value,
            description: descriptionField.value,
            priority: priorityField.value ?? "medium",
            dueDate: dueDateField.value,
            assigneeEmail: assigneeEmailField.value.isEmpty ? nil : assigneeEmailField.value,
            estimatedHours: estimatedHoursField.value
        )
    }
}

// MARK: - Profile Form

@MainActor
final class ProfileFormModel: ObservableObject {
    @Published var container: FormContainer

    let nameField: Archery.TextField
    let emailField: EmailField
    let passwordField: PasswordField
    let phoneField: Archery.TextField
    let websiteField: Archery.TextField
    let bioField: TextAreaField
    let birthdayField: DateField
    let receiveNewsletterField: BooleanField

    init() {
        nameField = Archery.TextField(
            id: "name",
            label: "Full Name",
            placeholder: "John Doe",
            isRequired: true,
            validators: [
                MinLengthValidator(minLength: 2),
                MaxLengthValidator(maxLength: 50)
            ]
        )

        emailField = EmailField(
            id: "email",
            label: "Email Address",
            placeholder: "you@example.com",
            isRequired: true
        )

        passwordField = PasswordField(
            id: "password",
            label: "Password",
            placeholder: "At least 8 characters",
            isRequired: true,
            minLength: 8,
            requireUppercase: true,
            requireNumbers: true
        )

        phoneField = Archery.TextField(
            id: "phone",
            label: "Phone Number",
            placeholder: "+1 (555) 123-4567",
            validators: [PhoneValidator()]
        )

        websiteField = Archery.TextField(
            id: "website",
            label: "Website",
            placeholder: "https://example.com",
            validators: [URLValidator()]
        )

        bioField = TextAreaField(
            id: "bio",
            label: "Bio",
            placeholder: "Tell us about yourself...",
            maxLength: 280,
            minLines: 2,
            maxLines: 4
        )

        birthdayField = DateField(
            id: "birthday",
            label: "Birthday",
            dateRange: Calendar.current.date(byAdding: .year, value: -100, to: Date())!...Date(),
            displayedComponents: .date
        )

        receiveNewsletterField = BooleanField(
            id: "newsletter",
            label: "Receive newsletter updates",
            helpText: "We'll send you updates about new features"
        )

        container = FormContainer(
            fields: [
                nameField,
                emailField,
                passwordField,
                phoneField,
                websiteField,
                bioField,
                birthdayField,
                receiveNewsletterField
            ]
        )
    }

    func validate() -> Bool {
        container.validateAllFields()
        return container.isValid
    }

    func reset() {
        container.reset()
    }
}

// MARK: - Form Showcase View

struct FormShowcaseView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Form Validation System")
                        .font(.headline)
                    Text("Typed fields, validators, real-time feedback, and form state management")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Demos") {
                NavigationLink {
                    TaskFormDemoView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Task Creation Form")
                            .font(.headline)
                        Text("Text, select, date, number fields with validation")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                NavigationLink {
                    ProfileFormDemoView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Profile Form")
                            .font(.headline)
                        Text("Email, password, phone, URL validators")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                NavigationLink {
                    ValidatorShowcaseView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Validator Gallery")
                            .font(.headline)
                        Text("All available validators demonstrated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Form Showcase")
    }
}

// MARK: - Task Form Demo View

struct TaskFormDemoView: View {
    @StateObject private var form = TaskFormModel()
    @State private var showingResult = false

    var body: some View {
        Form {
            Section("Task Details") {
                FormTextField(field: form.titleField)
                FormTextAreaField(field: form.descriptionField)
            }

            Section("Options") {
                FormSelectField(field: form.priorityField)
                FormDateField(field: form.dueDateField)
            }

            Section("Assignment") {
                FormTextField(field: form.assigneeEmailField)
                FormNumberField(field: form.estimatedHoursField)
            }

            Section {
                HStack {
                    Text("Form Valid:")
                    Spacer()
                    Image(systemName: form.container.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(form.container.isValid ? .green : .red)
                }

                Text("Errors: \(form.container.errors.count)")
                    .foregroundStyle(form.container.errors.isEmpty ? Color.secondary : Color.red)
            }

            Section {
                Button("Submit") {
                    if form.validate() {
                        showingResult = true
                    }
                }
                .disabled(!form.container.isValid)

                Button("Reset", role: .destructive) {
                    form.reset()
                }
            }
        }
        .navigationTitle("New Task")
        .alert("Task Created", isPresented: $showingResult) {
            Button("OK") {}
        } message: {
            let data = form.taskData
            Text("Title: \(data.title)\nPriority: \(data.priority)")
        }
    }
}

// MARK: - Profile Form Demo View

struct ProfileFormDemoView: View {
    @StateObject private var form = ProfileFormModel()
    @State private var showingResult = false

    var body: some View {
        Form {
            Section("Basic Info") {
                FormTextField(field: form.nameField)
                FormEmailField(field: form.emailField)
            }

            Section("Security") {
                FormPasswordField(field: form.passwordField)
            }

            Section("Contact") {
                FormTextField(field: form.phoneField)
                FormTextField(field: form.websiteField)
            }

            Section("About") {
                FormTextAreaField(field: form.bioField)
                FormDateField(field: form.birthdayField)
            }

            Section {
                FormBooleanField(field: form.receiveNewsletterField)
            }

            Section {
                HStack {
                    Text("Form Valid:")
                    Spacer()
                    Image(systemName: form.container.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(form.container.isValid ? .green : .red)
                }
            }

            Section {
                Button("Create Profile") {
                    if form.validate() {
                        showingResult = true
                    }
                }
                .disabled(!form.container.isValid)

                Button("Reset", role: .destructive) {
                    form.reset()
                }
            }
        }
        .navigationTitle("Profile")
        .alert("Profile Created", isPresented: $showingResult) {
            Button("OK") {}
        }
    }
}

// MARK: - Validator Showcase View

struct ValidatorShowcaseView: View {
    @State private var testValue = ""
    @State private var selectedValidator = "email"
    @State private var validationResult: [ValidationError] = []

    let validators: [(id: String, name: String, validator: any Validator<String>)] = [
        ("email", "Email", EmailValidator()),
        ("url", "URL", URLValidator()),
        ("phone", "Phone", PhoneValidator()),
        ("minLength", "Min Length (5)", MinLengthValidator(minLength: 5)),
        ("maxLength", "Max Length (10)", MaxLengthValidator(maxLength: 10)),
        ("required", "Required", RequiredValidator())
    ]

    var body: some View {
        Form {
            Section("Test Input") {
                TextField("Enter value to validate", text: $testValue)
                    .onChange(of: testValue) { _, _ in
                        validateCurrentInput()
                    }

                Picker("Validator", selection: $selectedValidator) {
                    ForEach(validators, id: \.id) { validator in
                        Text(validator.name).tag(validator.id)
                    }
                }
                .onChange(of: selectedValidator) { _, _ in
                    validateCurrentInput()
                }
            }

            Section("Result") {
                if validationResult.isEmpty {
                    Label("Valid", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(validationResult) { error in
                        Label(error.message, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Available Validators") {
                ForEach(validators, id: \.id) { validator in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(validator.name)
                            .font(.headline)
                        Text(validatorDescription(for: validator.id))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Validators")
    }

    private func validateCurrentInput() {
        guard let validator = validators.first(where: { $0.id == selectedValidator }) else { return }
        validationResult = validator.validator.validate(testValue, field: "Test")
    }

    private func validatorDescription(for id: String) -> String {
        switch id {
        case "email": return "RFC 5322 compliant email format"
        case "url": return "Valid URL with scheme and host"
        case "phone": return "E.164 international phone format"
        case "minLength": return "Minimum character count"
        case "maxLength": return "Maximum character count"
        case "required": return "Non-empty, non-whitespace value"
        default: return ""
        }
    }
}

// MARK: - Form Field Views

struct FormTextField: View {
    @ObservedObject var field: Archery.TextField

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(field.label)
                if field.isRequired {
                    Text("*").foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            SwiftUI.TextField(field.placeholder ?? "", text: Binding(
                get: { field.value },
                set: { field.value = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .onChange(of: field.value) { _, _ in
                _ = field.validate()
            }

            if let error = field.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let help = field.helpText, field.errors.isEmpty {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FormEmailField: View {
    @ObservedObject var field: EmailField

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(field.label)
                if field.isRequired {
                    Text("*").foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            SwiftUI.TextField(field.placeholder ?? "", text: Binding(
                get: { field.value },
                set: { field.value = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: field.value) { _, _ in
                _ = field.validate()
            }

            if let error = field.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

struct FormPasswordField: View {
    @ObservedObject var field: PasswordField
    @State private var showPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(field.label)
                if field.isRequired {
                    Text("*").foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Group {
                    if showPassword {
                        SwiftUI.TextField(field.placeholder ?? "", text: Binding(
                            get: { field.value },
                            set: { field.value = $0 }
                        ))
                    } else {
                        SecureField(field.placeholder ?? "", text: Binding(
                            get: { field.value },
                            set: { field.value = $0 }
                        ))
                    }
                }
                .textFieldStyle(.roundedBorder)
                .textContentType(.newPassword)
                .onChange(of: field.value) { _, _ in
                    _ = field.validate()
                }

                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
            }

            if let error = field.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Password strength indicator
            PasswordStrengthIndicator(password: field.value, requirements: (
                minLength: field.minLength,
                requireUppercase: field.requireUppercase,
                requireNumbers: field.requireNumbers
            ))
        }
    }
}

struct PasswordStrengthIndicator: View {
    let password: String
    let requirements: (minLength: Int, requireUppercase: Bool, requireNumbers: Bool)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            PasswordRequirementRow(met: password.count >= requirements.minLength, text: "\(requirements.minLength)+ characters")
            if requirements.requireUppercase {
                PasswordRequirementRow(met: password.contains(where: { $0.isUppercase }), text: "Uppercase letter")
            }
            if requirements.requireNumbers {
                PasswordRequirementRow(met: password.contains(where: { $0.isNumber }), text: "Number")
            }
        }
        .font(.caption2)
    }
}

struct PasswordRequirementRow: View {
    let met: Bool
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(met ? .green : .secondary)
                .font(.caption2)
            Text(text)
                .foregroundStyle(met ? .primary : .secondary)
        }
    }
}

struct FormTextAreaField: View {
    @ObservedObject var field: TextAreaField

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(field.label)
                if field.isRequired {
                    Text("*").foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            TextEditor(text: Binding(
                get: { field.value },
                set: { field.value = $0 }
            ))
            .frame(minHeight: CGFloat(field.minLines) * 20)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separator), lineWidth: 1)
            )
            .onChange(of: field.value) { _, _ in
                _ = field.validate()
            }

            HStack {
                if let error = field.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                } else if let help = field.helpText {
                    Text(help)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let maxLength = field.maxLength {
                    Text("\(field.value.count)/\(maxLength)")
                        .foregroundStyle(field.value.count > maxLength ? .red : .secondary)
                }
            }
            .font(.caption)
        }
    }
}

struct FormSelectField<T: Hashable>: View {
    @ObservedObject var field: SelectField<T>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(field.label)
                if field.isRequired {
                    Text("*").foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Picker(field.label, selection: Binding(
                get: { field.value },
                set: { field.value = $0 }
            )) {
                ForEach(field.options) { option in
                    HStack {
                        if let icon = option.icon {
                            Image(systemName: icon)
                        }
                        Text(option.label)
                    }
                    .tag(option.value as T?)
                }
            }
            .pickerStyle(.menu)
        }
    }
}

struct FormDateField: View {
    @ObservedObject var field: DateField

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(field.label)
                if field.isRequired {
                    Text("*").foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            datePickerContent

            if let help = field.helpText {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var datePickerContent: some View {
        if let range = field.dateRange {
            DatePicker(
                "",
                selection: Binding(
                    get: { field.value ?? Date() },
                    set: { field.value = $0 }
                ),
                in: range,
                displayedComponents: field.displayedComponents
            )
            .labelsHidden()
        } else {
            DatePicker(
                "",
                selection: Binding(
                    get: { field.value ?? Date() },
                    set: { field.value = $0 }
                ),
                displayedComponents: field.displayedComponents
            )
            .labelsHidden()
        }
    }
}

struct FormNumberField: View {
    @ObservedObject var field: NumberField
    @State private var textValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(field.label)
                if field.isRequired {
                    Text("*").foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            SwiftUI.TextField(field.placeholder ?? "", text: $textValue)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .onChange(of: textValue) { _, newValue in
                    field.value = Double(newValue)
                    _ = field.validate()
                }
                .onAppear {
                    if let value = field.value {
                        textValue = field.formatter.string(from: NSNumber(value: value)) ?? ""
                    }
                }

            if let error = field.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let help = field.helpText, field.errors.isEmpty {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FormBooleanField: View {
    @ObservedObject var field: BooleanField

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(field.label, isOn: Binding(
                get: { field.value },
                set: { field.value = $0 }
            ))

            if let help = field.helpText {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        FormShowcaseView()
    }
}
