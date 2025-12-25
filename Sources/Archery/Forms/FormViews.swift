import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Form View

public struct FormView<Content: View>: View {
    @Bindable var container: FormContainer
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
            #if os(iOS)
            .scrollDismissesKeyboard(configuration.keyboardDismissMode == .interactive ? .interactively : .immediately)
            #endif
            .onChange(of: container.focusedFieldId) { _, newValue in
                if let fieldId = newValue {
                    withAnimation {
                        proxy.scrollTo(fieldId, anchor: .center)
                    }
                }
            }
        }
        .environment(\.formConfiguration, configuration)
    }
}

// MARK: - Field Views

public struct FormFieldView: View {
    let field: any FormFieldProtocol
    @Environment(FormContainer.self) private var container
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

    #if os(tvOS) || os(watchOS)
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
        } else if let boolField = field as? BooleanField {
            ToggleFieldView(field: boolField)
        } else {
            Text("Unsupported field type")
                .foregroundColor(.secondary)
        }
    }
    #else
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
    #endif
}

// MARK: - Text Field Views

struct TextFieldView: View {
    @Bindable var field: TextField
    @Environment(FormContainer.self) private var container
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
            formConfig: configuration
        ))
        #if os(iOS) || os(tvOS) || os(visionOS)
        .keyboardType(field.keyboardType)
        .textContentType(field.textContentType)
        .textInputAutocapitalization(field.autocapitalization)
        #endif
        .autocorrectionDisabled(field.autocorrectionDisabled)
        .disabled(!field.isEnabled)
    }
}

struct SecureFieldView: View {
    @Bindable var field: PasswordField
    @Environment(FormContainer.self) private var container
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
                    formConfig: configuration
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
                    formConfig: configuration
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
    @Bindable var field: NumberField
    @Environment(FormContainer.self) private var container
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
            formConfig: configuration
        ))
        #if os(iOS) || os(tvOS) || os(visionOS)
        .keyboardType(.decimalPad)
        #endif
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

#if !os(tvOS) && !os(watchOS)
struct DateFieldView: View {
    @Bindable var field: DateField
    @Environment(FormContainer.self) private var container
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
#endif

struct ToggleFieldView: View {
    @Bindable var field: BooleanField
    @Environment(FormContainer.self) private var container

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

#if !os(tvOS) && !os(watchOS)
struct TextAreaView: View {
    @Bindable var field: TextAreaField
    @Environment(FormContainer.self) private var container
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
        .background(Color.gray.opacity(0.15))
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
#endif

// MARK: - Form Text Field Style

struct FormTextFieldStyle: TextFieldStyle {
    let hasError: Bool
    let isFocused: Bool
    let formConfig: FormConfiguration

    func _body(configuration: SwiftUI.TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(Color.gray.opacity(0.15))
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
            return formConfig.errorColor
        } else if isFocused {
            return formConfig.focusColor
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
    @Bindable var container: FormContainer
    let title: String

    public init(
        container: FormContainer,
        title: String = "Submit"
    ) {
        self.container = container
        self.title = title
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
