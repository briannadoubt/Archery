import SwiftUI
import Archery

// MARK: - Example App

struct FormExamplesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Login Form", destination: LoginFormView())
                NavigationLink("Registration Form", destination: RegistrationFormView())
                NavigationLink("Contact Form", destination: ContactFormView())
                NavigationLink("Survey Form", destination: SurveyFormView())
                NavigationLink("Profile Form", destination: ProfileFormView())
                NavigationLink("Payment Form", destination: PaymentFormView())
            }
            .navigationTitle("Form Examples")
        }
    }
}

// MARK: - Login Form

struct LoginFormView: View {
    @StateObject private var container = FormPreviewSeeds.validLoginForm()
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        FormView(container: container) {
            VStack(spacing: 20) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.accentColor)
                
                ForEach(container.fields, id: \.id) { field in
                    FormFieldView(field: field)
                }
                
                FormSubmitButton(container: container, title: "Sign In")
                
                Button("Forgot Password?") {
                    alertMessage = "Password reset link sent!"
                    showingAlert = true
                }
                .font(.caption)
            }
        }
        .navigationTitle("Login")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Success", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
}

// MARK: - Registration Form

@Form
struct RegistrationData {
    @Required @Label("First Name")
    var firstName: String = ""
    
    @Required @Label("Last Name")
    var lastName: String = ""
    
    @Required @Email @Label("Email Address")
    var email: String = ""
    
    @Required @MinLength(8) @Label("Password")
    var password: String = ""
    
    @Required @Label("Confirm Password")
    var confirmPassword: String = ""
    
    @Label("Phone Number") @Phone
    var phoneNumber: String = ""
    
    @Required @Label("Date of Birth")
    var dateOfBirth: Date = Date()
    
    @Label("Agree to Terms")
    var agreeToTerms: Bool = false
}

struct RegistrationFormView: View {
    @StateObject private var container: FormContainer
    
    init() {
        let fields: [any FormFieldProtocol] = [
            TextField(
                id: "firstName",
                label: "First Name",
                value: "",
                placeholder: "John",
                isRequired: true,
                validators: [MinLengthValidator(minLength: 2)]
            ),
            TextField(
                id: "lastName",
                label: "Last Name",
                value: "",
                placeholder: "Doe",
                isRequired: true,
                validators: [MinLengthValidator(minLength: 2)]
            ),
            EmailField(
                id: "email",
                label: "Email",
                value: "",
                isRequired: true
            ),
            PasswordField(
                id: "password",
                label: "Password",
                value: "",
                isRequired: true,
                minLength: 8,
                requireUppercase: true,
                requireNumbers: true
            ),
            PasswordField(
                id: "confirmPassword",
                label: "Confirm Password",
                value: "",
                isRequired: true
            ),
            TextField(
                id: "phone",
                label: "Phone Number",
                value: "",
                placeholder: "+1 (555) 123-4567",
                keyboardType: .phonePad,
                validators: [PhoneValidator()]
            ),
            DateField(
                id: "birthDate",
                label: "Date of Birth",
                value: nil,
                isRequired: true,
                dateRange: Date.distantPast...Date(),
                displayedComponents: [.date]
            ),
            BooleanField(
                id: "terms",
                label: "I agree to the Terms and Conditions",
                value: false
            )
        ]
        
        _container = StateObject(wrappedValue: FormContainer(
            fields: fields,
            validateOnBlur: true,
            onSubmit: {
                print("Registration submitted!")
            }
        ))
    }
    
    var body: some View {
        FormView(container: container) {
            ForEach(container.fields, id: \.id) { field in
                FormFieldView(field: field)
            }
            
            FormSubmitButton(container: container, title: "Create Account")
        }
        .navigationTitle("Registration")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Contact Form

struct ContactFormView: View {
    @StateObject private var container: FormContainer
    
    init() {
        let fields: [any FormFieldProtocol] = [
            TextField(
                id: "name",
                label: "Full Name",
                value: "",
                placeholder: "Your name",
                isRequired: true
            ),
            EmailField(
                id: "email",
                label: "Email",
                value: "",
                isRequired: true
            ),
            TextField(
                id: "subject",
                label: "Subject",
                value: "",
                placeholder: "What's this about?",
                isRequired: true
            ),
            TextAreaField(
                id: "message",
                label: "Message",
                value: "",
                placeholder: "Your message here...",
                isRequired: true,
                minLines: 5,
                validators: [MinLengthValidator(minLength: 20)]
            )
        ]
        
        _container = StateObject(wrappedValue: FormContainer(fields: fields))
    }
    
    var body: some View {
        FormView(container: container) {
            ForEach(container.fields, id: \.id) { field in
                FormFieldView(field: field)
            }
            
            FormSubmitButton(container: container, title: "Send Message")
        }
        .navigationTitle("Contact Us")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Survey Form

struct SurveyFormView: View {
    @StateObject private var container: FormContainer
    
    init() {
        let fields: [any FormFieldProtocol] = [
            NumberField(
                id: "rating",
                label: "Overall Satisfaction (1-10)",
                value: nil,
                placeholder: "Enter a number",
                isRequired: true,
                range: 1...10
            ),
            SelectField<String>(
                id: "frequency",
                label: "How often do you use our service?",
                value: nil,
                options: [
                    .init(value: "daily", label: "Daily"),
                    .init(value: "weekly", label: "Weekly"),
                    .init(value: "monthly", label: "Monthly"),
                    .init(value: "rarely", label: "Rarely")
                ],
                isRequired: true
            ),
            BooleanField(
                id: "recommend",
                label: "Would you recommend us to a friend?",
                value: false
            ),
            TextAreaField(
                id: "improvements",
                label: "What can we improve?",
                value: "",
                placeholder: "Your suggestions...",
                maxLength: 500
            ),
            TextAreaField(
                id: "feedback",
                label: "Additional Feedback",
                value: "",
                placeholder: "Anything else you'd like to share?",
                minLines: 3,
                maxLines: 10
            )
        ]
        
        _container = StateObject(wrappedValue: FormContainer(fields: fields))
    }
    
    var body: some View {
        FormView(container: container) {
            ForEach(container.fields, id: \.id) { field in
                FormFieldView(field: field)
            }
            
            FormSubmitButton(container: container, title: "Submit Survey")
        }
        .navigationTitle("Customer Survey")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Profile Form

struct ProfileFormView: View {
    @StateObject private var container: FormContainer
    @State private var showingImagePicker = false
    
    init() {
        let fields: [any FormFieldProtocol] = [
            TextField(
                id: "username",
                label: "Username",
                value: "johndoe",
                validators: [
                    MinLengthValidator(minLength: 3),
                    RegexValidator(
                        pattern: "^[a-zA-Z0-9_]+$",
                        message: "Username can only contain letters, numbers, and underscores"
                    )
                ]
            ),
            TextField(
                id: "displayName",
                label: "Display Name",
                value: "John Doe",
                isRequired: true
            ),
            EmailField(
                id: "email",
                label: "Email",
                value: "john@example.com",
                isRequired: true
            ),
            TextAreaField(
                id: "bio",
                label: "Bio",
                value: "",
                placeholder: "Tell us about yourself",
                maxLength: 200,
                minLines: 3
            ),
            TextField(
                id: "website",
                label: "Website",
                value: "",
                placeholder: "https://yourwebsite.com",
                validators: [URLValidator()]
            ),
            TextField(
                id: "location",
                label: "Location",
                value: "",
                placeholder: "City, Country"
            ),
            BooleanField(
                id: "publicProfile",
                label: "Make profile public",
                value: true
            ),
            BooleanField(
                id: "emailNotifications",
                label: "Email notifications",
                value: true
            )
        ]
        
        _container = StateObject(wrappedValue: FormContainer(fields: fields))
    }
    
    var body: some View {
        FormView(container: container) {
            VStack(alignment: .center, spacing: 20) {
                Button(action: { showingImagePicker = true }) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.secondary)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                                .offset(x: 25, y: 25)
                        )
                }
                .buttonStyle(.plain)
                
                ForEach(container.fields, id: \.id) { field in
                    FormFieldView(field: field)
                }
                
                FormSubmitButton(container: container, title: "Update Profile")
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Payment Form

struct PaymentFormView: View {
    @StateObject private var container: FormContainer
    
    init() {
        let fields: [any FormFieldProtocol] = [
            TextField(
                id: "cardholderName",
                label: "Cardholder Name",
                value: "",
                placeholder: "Name on card",
                isRequired: true
            ),
            TextField(
                id: "cardNumber",
                label: "Card Number",
                value: "",
                placeholder: "1234 5678 9012 3456",
                isRequired: true,
                keyboardType: .numberPad,
                validators: [
                    RegexValidator(
                        pattern: "^[0-9]{13,19}$",
                        message: "Invalid card number"
                    )
                ]
            ),
            TextField(
                id: "expiryDate",
                label: "Expiry Date",
                value: "",
                placeholder: "MM/YY",
                isRequired: true,
                validators: [
                    RegexValidator(
                        pattern: "^(0[1-9]|1[0-2])\\/[0-9]{2}$",
                        message: "Use format MM/YY"
                    )
                ]
            ),
            TextField(
                id: "cvv",
                label: "CVV",
                value: "",
                placeholder: "123",
                helpText: "3 or 4 digit security code",
                isRequired: true,
                keyboardType: .numberPad,
                validators: [
                    RegexValidator(
                        pattern: "^[0-9]{3,4}$",
                        message: "Invalid CVV"
                    )
                ]
            ),
            TextField(
                id: "billingZip",
                label: "Billing ZIP Code",
                value: "",
                placeholder: "12345",
                isRequired: true,
                keyboardType: .numberPad
            ),
            BooleanField(
                id: "saveCard",
                label: "Save card for future purchases",
                value: false
            )
        ]
        
        _container = StateObject(wrappedValue: FormContainer(
            fields: fields,
            validateOnChange: true
        ))
    }
    
    var body: some View {
        FormView(container: container) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Payment Information")
                    .font(.headline)
                
                ForEach(container.fields, id: \.id) { field in
                    FormFieldView(field: field)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Your payment information is secure and encrypted")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                FormSubmitButton(container: container, title: "Process Payment")
            }
        }
        .navigationTitle("Payment")
        .navigationBarTitleDisplayMode(.inline)
    }
}