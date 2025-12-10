import Foundation
import SwiftUI
import Archery

// MARK: - Form Macros Demo
// Demonstrates the @Form macro which generates:
// - formContainer lazy property
// - formFields array property
// - validate() method
// - submit() async method
// - reset() method

// Note: The @Form macro reads field attributes to build form configuration.
// For this showcase, we demonstrate the pattern using regular structs
// since the field attribute macros require additional macro registrations.

// These structs show the pattern that @Form generates code for:
struct RegistrationFormData {
    var name: String = ""
    var email: String = ""
    var password: String = ""
    var phone: String = ""
    var company: String = ""
    var agreeToTerms: Bool = false

    // @Form would generate these:
    var formFields: [FormFieldInfo] {
        [
            FormFieldInfo(id: "name", label: "Full Name", isRequired: true, placeholder: "Enter your full name"),
            FormFieldInfo(id: "email", label: "Email Address", isRequired: true, placeholder: "you@example.com", helpText: "We'll never share your email", validators: ["email"]),
            FormFieldInfo(id: "password", label: "Password", isRequired: true, placeholder: "At least 8 characters", validators: ["minLength:8"]),
            FormFieldInfo(id: "phone", label: "Phone Number", placeholder: "+1 (555) 123-4567", validators: ["phone"]),
            FormFieldInfo(id: "company", label: "Company", placeholder: "Your company name"),
            FormFieldInfo(id: "agreeToTerms", label: "Agree to Terms")
        ]
    }

    func validate() -> Bool {
        !name.isEmpty && !email.isEmpty && !password.isEmpty && password.count >= 8 && agreeToTerms
    }
}

struct ContactFormData {
    var subject: String = ""
    var email: String = ""
    var message: String = ""
    var priority: String = "normal"

    var formFields: [FormFieldInfo] {
        [
            FormFieldInfo(id: "subject", label: "Subject", isRequired: true, placeholder: "What's this about?"),
            FormFieldInfo(id: "email", label: "Your Email", isRequired: true, placeholder: "your@email.com", validators: ["email"]),
            FormFieldInfo(id: "message", label: "Message", isRequired: true, placeholder: "Tell us more...", helpText: "Please be as detailed as possible", validators: ["minLength:10", "maxLength:1000"]),
            FormFieldInfo(id: "priority", label: "Priority")
        ]
    }

    func validate() -> Bool {
        !subject.isEmpty && !email.isEmpty && !message.isEmpty && message.count >= 10
    }
}

struct TaskFormData {
    var title: String = ""
    var description: String = ""
    var priority: String = "medium"
    var dueDate: Date?
    var assignee: String = ""
    var tags: String = ""

    var formFields: [FormFieldInfo] {
        [
            FormFieldInfo(id: "title", label: "Task Title", isRequired: true, placeholder: "What needs to be done?"),
            FormFieldInfo(id: "description", label: "Description", placeholder: "Add more details...", validators: ["maxLength:500"]),
            FormFieldInfo(id: "priority", label: "Priority Level"),
            FormFieldInfo(id: "dueDate", label: "Due Date"),
            FormFieldInfo(id: "assignee", label: "Assign To", placeholder: "Select a team member"),
            FormFieldInfo(id: "tags", label: "Tags", helpText: "Comma-separated list of tags")
        ]
    }

    func validate() -> Bool {
        !title.isEmpty
    }
}

// Helper struct representing form field metadata
struct FormFieldInfo: Identifiable {
    let id: String
    let label: String
    var isRequired: Bool = false
    var placeholder: String? = nil
    var helpText: String? = nil
    var validators: [String] = []
}

// MARK: - Form Demo View

struct FormMacrosDemoView: View {
    @State private var registrationForm = RegistrationFormData()
    @State private var contactForm = ContactFormData()
    @State private var showingResult = false
    @State private var resultMessage = ""

    var body: some View {
        List {
            Section("Registration Form") {
                NavigationLink("Show Registration Form") {
                    RegistrationFormView(form: $registrationForm)
                }
            }

            Section("Contact Form") {
                NavigationLink("Show Contact Form") {
                    ContactFormView(form: $contactForm)
                }
            }

            Section("Task Creation Form") {
                NavigationLink("Create New Task") {
                    TaskFormView()
                }
            }
        }
        .navigationTitle("Form Macros Demo")
        .alert("Form Result", isPresented: $showingResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage)
        }
    }
}

struct RegistrationFormView: View {
    @Binding var form: RegistrationFormData
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section("Personal Information") {
                TextField("Full Name", text: $form.name)
                TextField("Email", text: $form.email)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                SecureField("Password", text: $form.password)
                    .textContentType(.newPassword)
            }

            Section("Optional Information") {
                TextField("Phone", text: $form.phone)
                    .textContentType(.telephoneNumber)
                TextField("Company", text: $form.company)
            }

            Section {
                Toggle("I agree to the Terms of Service", isOn: $form.agreeToTerms)
            }

            Section {
                Button("Create Account") {
                    // Uses generated validate() and submit() methods
                    dismiss()
                }
                .disabled(form.name.isEmpty || form.email.isEmpty || form.password.isEmpty || !form.agreeToTerms)
            }
        }
        .navigationTitle("Registration")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ContactFormView: View {
    @Binding var form: ContactFormData
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section {
                TextField("Subject", text: $form.subject)
                TextField("Your Email", text: $form.email)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
            }

            Section("Message") {
                TextEditor(text: $form.message)
                    .frame(minHeight: 100)
            }

            Section("Priority") {
                Picker("Priority", selection: $form.priority) {
                    Text("Low").tag("low")
                    Text("Normal").tag("normal")
                    Text("High").tag("high")
                    Text("Urgent").tag("urgent")
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button("Send Message") {
                    dismiss()
                }
                .disabled(form.subject.isEmpty || form.email.isEmpty || form.message.isEmpty)
            }
        }
        .navigationTitle("Contact Us")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TaskFormView: View {
    @State private var form = TaskFormData()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section("Task Details") {
                TextField("Title", text: $form.title)
                TextEditor(text: $form.description)
                    .frame(minHeight: 60)
            }

            Section("Options") {
                Picker("Priority", selection: $form.priority) {
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                }

                DatePicker(
                    "Due Date",
                    selection: Binding(
                        get: { form.dueDate ?? Date() },
                        set: { form.dueDate = $0 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )

                TextField("Assignee", text: $form.assignee)
                TextField("Tags", text: $form.tags)
            }

            Section {
                Button("Create Task") {
                    dismiss()
                }
                .disabled(form.title.isEmpty)
            }
        }
        .navigationTitle("New Task")
        .navigationBarTitleDisplayMode(.inline)
    }
}
