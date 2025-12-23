import SwiftUI

// MARK: - Wizard Form View

struct WizardFormView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentStep = 0
    @State private var name = ""
    @State private var email = ""
    @State private var company = ""
    @State private var role = ""

    private let steps = ["Personal Info", "Work Details", "Review"]

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 0) {
                ForEach(0..<steps.count, id: \.self) { index in
                    StepIndicator(index: index, title: steps[index], isCompleted: index < currentStep, isCurrent: index == currentStep)
                    if index < steps.count - 1 {
                        Rectangle().fill(index < currentStep ? Color.accentColor : Color.gray.opacity(0.3)).frame(height: 2)
                    }
                }
            }
            .padding()

            Spacer()

            // Step content
            Group {
                switch currentStep {
                case 0: PersonalInfoStep(name: $name, email: $email)
                case 1: WorkDetailsStep(company: $company, role: $role)
                case 2: ReviewStep(name: name, email: email, company: company, role: role)
                default: EmptyView()
                }
            }
            .padding()

            Spacer()

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") { withAnimation { currentStep -= 1 } }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button(currentStep == steps.count - 1 ? "Submit" : "Next") {
                    if currentStep == steps.count - 1 {
                        dismiss()
                    } else {
                        withAnimation { currentStep += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentStep == 0 && (name.isEmpty || email.isEmpty))
                .disabled(currentStep == 1 && company.isEmpty)
            }
            .padding()
        }
        .navigationTitle("Wizard Form")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Wizard Step Views

private struct StepIndicator: View {
    let index: Int
    let title: String
    let isCompleted: Bool
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.accentColor : (isCurrent ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.2)))
                    .frame(width: 32, height: 32)
                if isCompleted {
                    Image(systemName: "checkmark").foregroundStyle(.white).font(.caption.bold())
                } else {
                    Text("\(index + 1)").foregroundStyle(isCurrent ? Color.accentColor : .secondary).font(.caption.bold())
                }
            }
            Text(title).font(.caption2).foregroundStyle(isCurrent ? .primary : .secondary)
        }
    }
}

private struct PersonalInfoStep: View {
    @Binding var name: String
    @Binding var email: String

    var body: some View {
        VStack(spacing: 16) {
            Text("Personal Information").font(.title2).fontWeight(.semibold)
            TextField("Full Name", text: $name).textFieldStyle(.roundedBorder)
            TextField("Email Address", text: $email).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).keyboardType(.emailAddress)
        }
    }
}

private struct WorkDetailsStep: View {
    @Binding var company: String
    @Binding var role: String

    var body: some View {
        VStack(spacing: 16) {
            Text("Work Details").font(.title2).fontWeight(.semibold)
            TextField("Company Name", text: $company).textFieldStyle(.roundedBorder)
            TextField("Your Role", text: $role).textFieldStyle(.roundedBorder)
        }
    }
}

private struct ReviewStep: View {
    let name: String
    let email: String
    let company: String
    let role: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review").font(.title2).fontWeight(.semibold)
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ReviewRow(label: "Name", value: name)
                    ReviewRow(label: "Email", value: email)
                    ReviewRow(label: "Company", value: company)
                    ReviewRow(label: "Role", value: role.isEmpty ? "Not specified" : role)
                }
            }
        }
    }
}

private struct ReviewRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }
}

// MARK: - Auth Views

struct SignUpView: View {
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Full Name", text: $name) }
                Section { TextField("Email", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress) }
                Section {
                    SecureField("Password", text: $password)
                    SecureField("Confirm Password", text: $confirmPassword)
                }
                Section {
                    Button("Create Account") { dismiss() }
                        .disabled(email.isEmpty || password.isEmpty || password != confirmPassword)
                }
            }
            .navigationTitle("Sign Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

struct ForgotPasswordView: View {
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            if submitted {
                ContentUnavailableView("Check Your Email", systemImage: "envelope.badge", description: Text("We've sent password reset instructions to \(email)"))
            } else {
                Form {
                    Section {
                        TextField("Email Address", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    } footer: {
                        Text("Enter the email associated with your account.")
                    }
                    Section {
                        Button("Send Reset Link") { withAnimation { submitted = true } }.disabled(email.isEmpty)
                    }
                }
            }
        }
        .navigationTitle("Forgot Password")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }
}

// MARK: - Task Detail View

struct TaskDetailView: View {
    let taskId: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Task Details").font(.largeTitle).fontWeight(.bold).padding(.horizontal)
                Text("Task ID: \(taskId)").font(.subheadline.monospaced()).foregroundStyle(.secondary).padding(.horizontal)
                Text("This view would show detailed task information.").padding(.horizontal)
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - New Task View

struct NewTaskView: View {
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var priority: TaskPriority = .medium
    @State private var dueDate = Date()
    @State private var hasDueDate = false

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Task Title", text: $title) }
                Section { TextField("Description", text: $description, axis: .vertical).lineLimit(3...6) }
                Section {
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { priority in
                            Label(priority.title, systemImage: priority.icon).tag(priority)
                        }
                    }
                }
                Section {
                    Toggle("Set Due Date", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create") { dismiss() }.disabled(title.isEmpty) }
            }
        }
    }
}
