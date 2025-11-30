import SwiftUI

// MARK: - Form View

public struct FormView<Content: View>: View {
    @ObservedObject var container: FormContainer
    @StateObject private var focusManager = FocusStateManager()
    let configuration: FormConfiguration
    let content: () -> Content
    
    public init(
        container: FormContainer,
        configuration: FormConfiguration = .default,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.container = container
        self.configuration = configuration
        self.content = content
    }
    
    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: configuration.spacing) {
                    content()
                }
                .padding()
            }
            .scrollDismissesKeyboard(configuration.keyboardDismissMode)
            .onChange(of: container.focusedFieldId) { _, newValue in
                if let fieldId = newValue {
                    withAnimation {
                        proxy.scrollTo(fieldId, anchor: .center)
                    }
                }
            }
        }
        .environmentObject(focusManager)
        .environment(\.formConfiguration, configuration)
    }
}

// MARK: - Field Views

public struct FormFieldView: View {
    let field: any FormFieldProtocol
    @EnvironmentObject private var container: FormContainer
    @EnvironmentObject private var focusManager: FocusStateManager
    @Environment(\.formConfiguration) private var configuration
    @FocusState private var isFocused: Bool
    
    public init(field: any FormFieldProtocol) {
        self.field = field
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            labelView
            
            fieldContent
                .id(field.id)
                .focused($isFocused)
                .onChange(of: isFocused) { _, newValue in
                    if newValue {
                        container.focusField(id: field.id)
                    } else if container.focusedFieldId == field.id {
                        container.focusField(id: nil)
                    }
                }
            
            if let helpText = field.helpText, field.errors.isEmpty {
                Text(helpText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let error = field.errors.first {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(error.message)
                        .font(.caption)
                }
                .foregroundColor(configuration.errorColor)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: configuration.animationDuration), value: field.errors.isEmpty)
    }
    
    private var labelView: some View {
        HStack(spacing: 2) {
            Text(field.label)
                .font(.subheadline)
                .fontWeight(.medium)
            
            if field.isRequired && configuration.showRequiredIndicator {
                Text(configuration.requiredIndicator)
                    .foregroundColor(configuration.errorColor)
            }
        }
    }
    
    @ViewBuilder
    private var fieldContent: some View {
        if let textField = field as? TextField {
            TextFieldView(field: textField)
        } else if let emailField = field as? EmailField {
            TextFieldView(field: emailField)
        } else if let passwordField = field as? PasswordField {
            SecureFieldView(field: passwordField)
        } else if let numberField = field as? NumberField {
            NumberFieldView(field: numberField)
        } else if let dateField = field as? DateField {
            DateFieldView(field: dateField)
        } else if let boolField = field as? BooleanField {
            ToggleFieldView(field: boolField)
        } else if let textAreaField = field as? TextAreaField {
            TextAreaView(field: textAreaField)
        } else {
            Text("Unsupported field type")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Text Field Views

struct TextFieldView: View {
    @ObservedObject var field: TextField
    @EnvironmentObject private var container: FormContainer
    @Environment(\.formConfiguration) private var configuration
    
    var body: some View {
        SwiftUI.TextField(
            field.placeholder ?? field.label,
            text: Binding(
                get: { field.value },
                set: { container.updateField(id: field.id, value: $0) }
            )
        )
        .textFieldStyle(FormTextFieldStyle(
            hasError: !field.errors.isEmpty,
            isFocused: field.isFocused,
            configuration: configuration
        ))
        .keyboardType(field.keyboardType)
        .textContentType(field.textContentType)
        .autocapitalization(field.autocapitalization)
        .autocorrectionDisabled(field.autocorrectionDisabled)
        .disabled(!field.isEnabled)
    }
}

struct SecureFieldView: View {
    @ObservedObject var field: PasswordField
    @EnvironmentObject private var container: FormContainer
    @Environment(\.formConfiguration) private var configuration
    @State private var isSecure = true
    
    var body: some View {
        HStack {
            if isSecure {
                SecureField(
                    field.placeholder ?? field.label,
                    text: Binding(
                        get: { field.value },
                        set: { container.updateField(id: field.id, value: $0) }
                    )
                )
                .textFieldStyle(FormTextFieldStyle(
                    hasError: !field.errors.isEmpty,
                    isFocused: field.isFocused,
                    configuration: configuration
                ))
            } else {
                SwiftUI.TextField(
                    field.placeholder ?? field.label,
                    text: Binding(
                        get: { field.value },
                        set: { container.updateField(id: field.id, value: $0) }
                    )
                )
                .textFieldStyle(FormTextFieldStyle(
                    hasError: !field.errors.isEmpty,
                    isFocused: field.isFocused,
                    configuration: configuration
                ))
            }
            
            Button(action: { isSecure.toggle() }) {
                Image(systemName: isSecure ? "eye.slash" : "eye")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .disabled(!field.isEnabled)
    }
}

struct NumberFieldView: View {
    @ObservedObject var field: NumberField
    @EnvironmentObject private var container: FormContainer
    @Environment(\.formConfiguration) private var configuration
    @State private var text = ""
    
    var body: some View {
        SwiftUI.TextField(
            field.placeholder ?? field.label,
            text: $text
        )
        .textFieldStyle(FormTextFieldStyle(
            hasError: !field.errors.isEmpty,
            isFocused: field.isFocused,
            configuration: configuration
        ))
        .keyboardType(.decimalPad)
        .disabled(!field.isEnabled)
        .onAppear {
            if let value = field.value {
                text = field.formatter.string(from: NSNumber(value: value)) ?? ""
            }
        }
        .onChange(of: text) { _, newValue in
            if let number = field.formatter.number(from: newValue) {
                container.updateField(id: field.id, value: number.doubleValue)
            }
        }
    }
}

struct DateFieldView: View {
    @ObservedObject var field: DateField
    @EnvironmentObject private var container: FormContainer
    @Environment(\.formConfiguration) private var configuration
    
    var body: some View {
        DatePicker(
            "",
            selection: Binding(
                get: { field.value ?? Date() },
                set: { container.updateField(id: field.id, value: $0) }
            ),
            displayedComponents: field.displayedComponents
        )
        .datePickerStyle(.compact)
        .labelsHidden()
        .disabled(!field.isEnabled)
    }
}

struct ToggleFieldView: View {
    @ObservedObject var field: BooleanField
    @EnvironmentObject private var container: FormContainer
    
    var body: some View {
        Toggle(
            "",
            isOn: Binding(
                get: { field.value },
                set: { container.updateField(id: field.id, value: $0) }
            )
        )
        .labelsHidden()
        .disabled(!field.isEnabled)
    }
}

struct TextAreaView: View {
    @ObservedObject var field: TextAreaField
    @EnvironmentObject private var container: FormContainer
    @Environment(\.formConfiguration) private var configuration
    
    var body: some View {
        TextEditor(
            text: Binding(
                get: { field.value },
                set: { container.updateField(id: field.id, value: $0) }
            )
        )
        .frame(minHeight: CGFloat(field.minLines * 20))
        .frame(maxHeight: field.maxLines.map { CGFloat($0 * 20) })
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    field.errors.isEmpty ? Color.clear : configuration.errorColor,
                    lineWidth: field.errors.isEmpty ? 0 : 2
                )
        )
        .disabled(!field.isEnabled)
    }
}

// MARK: - Form Text Field Style

struct FormTextFieldStyle: TextFieldStyle {
    let hasError: Bool
    let isFocused: Bool
    let configuration: FormConfiguration
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        strokeColor,
                        lineWidth: strokeWidth
                    )
            )
    }
    
    private var strokeColor: Color {
        if hasError {
            return configuration.errorColor
        } else if isFocused {
            return configuration.focusColor
        } else {
            return Color.clear
        }
    }
    
    private var strokeWidth: CGFloat {
        hasError || isFocused ? 2 : 0
    }
}

// MARK: - Form Submit Button

public struct FormSubmitButton: View {
    @ObservedObject var container: FormContainer
    let title: String
    let style: ButtonStyle
    
    public init(
        container: FormContainer,
        title: String = "Submit",
        style: ButtonStyle = .borderedProminent
    ) {
        self.container = container
        self.title = title
        self.style = style
    }
    
    public var body: some View {
        Button(action: {
            Task {
                try? await container.submit()
            }
        }) {
            if container.isSubmitting {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                Text(title)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!container.isValid || container.isSubmitting)
    }
}

// MARK: - Environment Key

private struct FormConfigurationKey: EnvironmentKey {
    static let defaultValue = FormConfiguration.default
}

extension EnvironmentValues {
    var formConfiguration: FormConfiguration {
        get { self[FormConfigurationKey.self] }
        set { self[FormConfigurationKey.self] = newValue }
    }
}