import SwiftUI

// MARK: - Form Examples View
struct FormExamplesView: View {
    @State private var registrationForm = RegistrationFormData()
    @State private var contactForm = ContactFormData()

    var body: some View {
        List {
            Section("Basic Forms") {
                NavigationLink {
                    RegistrationFormView(form: $registrationForm)
                } label: {
                    FormRowLabel(
                        title: "Registration Form",
                        description: "User sign-up with validation",
                        icon: "person.badge.plus"
                    )
                }

                NavigationLink {
                    ContactFormView(form: $contactForm)
                } label: {
                    FormRowLabel(
                        title: "Contact Form",
                        description: "Support request with priority",
                        icon: "envelope"
                    )
                }

                NavigationLink {
                    TaskFormView()
                } label: {
                    FormRowLabel(
                        title: "Task Form",
                        description: "Create task with metadata",
                        icon: "checklist"
                    )
                }
            }

            Section("Advanced Forms") {
                NavigationLink {
                    WizardFormView()
                } label: {
                    FormRowLabel(
                        title: "Multi-Step Wizard",
                        description: "Step-by-step onboarding flow",
                        icon: "rectangle.stack"
                    )
                }
            }

            Section("Navigation & Flows") {
                NavigationLink {
                    NavigationShowcaseView()
                } label: {
                    FormRowLabel(
                        title: "Navigation Demo",
                        description: "@Route, @Flow, @presents, deep links",
                        icon: "arrow.triangle.branch"
                    )
                }

                NavigationLink {
                    TaskCreationFlowHost()
                } label: {
                    FormRowLabel(
                        title: "Task Creation Flow",
                        description: "@Flow wizard with 4 steps",
                        icon: "rectangle.stack.badge.plus"
                    )
                }
            }
        }
        .navigationTitle("Forms")
    }
}

// Helper view for form list rows
private struct FormRowLabel: View {
    let title: String
    let description: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Wizard Form View (Multi-Step Form Demo)
struct WizardFormView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentStep = 0
    @State private var name = ""
    @State private var email = ""
    @State private var role = "Developer"
    @State private var experience = "1-3 years"
    @State private var notifications = true
    @State private var newsletter = false

    private let roles = ["Developer", "Designer", "Product Manager", "QA Engineer", "Other"]
    private let experienceLevels = ["Less than 1 year", "1-3 years", "3-5 years", "5+ years"]

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator

            TabView(selection: $currentStep) {
                step1.tag(0)
                step2.tag(1)
                step3.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentStep)

            navigationButtons
        }
        .navigationTitle("Onboarding")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { step in
                Capsule()
                    .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(height: 4)
            }
        }
        .padding()
    }

    private var step1: some View {
        Form {
            Section {
                Text("Let's get to know you")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Section("Personal Information") {
                TextField("Full Name", text: $name)
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
            }
        }
    }

    private var step2: some View {
        Form {
            Section {
                Text("Tell us about your work")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Section("Professional Details") {
                Picker("Role", selection: $role) {
                    ForEach(roles, id: \.self) { Text($0) }
                }

                Picker("Experience", selection: $experience) {
                    ForEach(experienceLevels, id: \.self) { Text($0) }
                }
            }
        }
    }

    private var step3: some View {
        Form {
            Section {
                Text("Almost done!")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Section("Preferences") {
                Toggle("Push Notifications", isOn: $notifications)
                Toggle("Newsletter", isOn: $newsletter)
            }

            Section("Summary") {
                LabeledContent("Name", value: name.isEmpty ? "Not provided" : name)
                LabeledContent("Email", value: email.isEmpty ? "Not provided" : email)
                LabeledContent("Role", value: role)
                LabeledContent("Experience", value: experience)
            }
        }
    }

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") {
                    currentStep -= 1
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if currentStep < 2 {
                Button("Next") {
                    currentStep += 1
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isStepValid)
            } else {
                Button("Complete") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isStepValid)
            }
        }
        .padding()
    }

    private var isStepValid: Bool {
        switch currentStep {
        case 0: return !name.isEmpty && !email.isEmpty
        case 1: return true
        case 2: return true
        default: return true
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @Environment(\.navigationHandle) private var nav

    var body: some View {
        List {
            Section("Account") {
                NavigationLink("Profile", destination: ProfileView())
                NavigationLink("Subscription", destination: SubscriptionView())
                NavigationLink("Privacy", destination: Text("Privacy Settings").navigationTitle("Privacy"))
            }

            Section("Preferences") {
                NavigationLink("Appearance", destination: AppearanceView())
                NavigationLink("Notifications", destination: NotificationsSettingsView())
                NavigationLink("Data & Storage", destination: Text("Data & Storage").navigationTitle("Data & Storage"))
            }

            Section("Developer") {
                NavigationLink {
                    AnalyticsShowcaseView()
                } label: {
                    Label("Analytics & Events", systemImage: "chart.bar.xaxis")
                }

                NavigationLink {
                    ObservabilityShowcaseView()
                } label: {
                    Label("Observability Dashboard", systemImage: "waveform.path.ecg")
                }

                NavigationLink {
                    MonetizationShowcaseView()
                } label: {
                    Label("StoreKit & Monetization", systemImage: "creditcard")
                }

                NavigationLink {
                    GRDBShowcaseView()
                } label: {
                    Label("GRDB Persistence", systemImage: "cylinder.split.1x2")
                }

                NavigationLink("Macro Showcase", destination: MacroShowcaseView())
                NavigationLink("Advanced Macros", destination: AdvancedMacrosShowcaseView())
                NavigationLink("App Intents", destination: AppIntentsShowcaseView())
                NavigationLink("Widget Setup", destination: WidgetSharedPreview())
                NavigationLink("Routes & Deep Links", destination: DeepLinkTesterView())
                NavigationLink("Design Tokens", destination: DesignTokensShowcaseView())
                NavigationLink("@ViewModelBound", destination: ViewModelBoundShowcaseView())
                NavigationLink("@AppShell", destination: AppShellShowcaseView())
                NavigationLink("@SharedModel", destination: SharedModelShowcaseView())
            }

            Section("About") {
                NavigationLink("Help & Support", destination: Text("Help").navigationTitle("Help"))
                NavigationLink("Terms of Service", destination: Text("Terms").navigationTitle("Terms"))
                NavigationLink("Privacy Policy", destination: Text("Privacy").navigationTitle("Privacy"))
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Appearance View
struct AppearanceView: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $themeManager.currentTheme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Label(theme.displayName, systemImage: theme.icon)
                            .tag(theme)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Preview") {
                previewColors
            }

            Section {
                Text("Theme changes are applied immediately and saved automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Appearance")
    }

    private var previewColors: some View {
        HStack(spacing: 16) {
            colorSwatch(color: Color.accentColor, label: "Accent")
            colorSwatch(color: Color(.systemBackground), label: "Background")
            colorSwatch(color: Color(.secondarySystemBackground), label: "Secondary")
        }
    }

    private func colorSwatch(color: Color, label: String) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(color)
            .frame(height: 60)
            .overlay {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(label == "Accent" ? .white : .primary)
            }
    }
}

// MARK: - Notifications Settings View
struct NotificationsSettingsView: View {
    @State private var pushEnabled = true
    @State private var taskReminders = true
    @State private var dailySummary = false
    @State private var weeklyReport = true

    var body: some View {
        Form {
            Section("Push Notifications") {
                Toggle("Enable Notifications", isOn: $pushEnabled)
            }

            Section("Reminders") {
                Toggle("Task Reminders", isOn: $taskReminders)
                    .disabled(!pushEnabled)
                Toggle("Daily Summary", isOn: $dailySummary)
                    .disabled(!pushEnabled)
                Toggle("Weekly Report", isOn: $weeklyReport)
                    .disabled(!pushEnabled)
            }

            Section {
                Text("Manage notification permissions in System Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Notifications")
    }
}

// MARK: - Deep Link Tester View
struct DeepLinkTesterView: View {
    @State private var urlText = "tasks/list"
    @State private var matchedRoute: String?

    var body: some View {
        Form {
            Section("Test URL Path") {
                TextField("Enter path (e.g., tasks/list)", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Test Route") {
                    testRoute()
                }
            }

            Section("Result") {
                if let route = matchedRoute {
                    Label(route, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("No match", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Available Routes") {
                Group {
                    Text("dashboard/main, dashboard/stats, dashboard/insights")
                    Text("tasks/list, tasks/create, tasks/{id}")
                    Text("forms/list, forms/registration, forms/contact")
                    Text("settings/main, settings/profile, settings/preferences")
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Deep Links")
    }

    private func testRoute() {
        let path = urlText.split(separator: "/").map(String.init)

        // Try each route type
        if let route = TasksRoute.fromURL(path: path, query: [:]) {
            matchedRoute = "TasksRoute.\(route)"
        } else if let route = DashboardRoute.fromURL(path: path, query: [:]) {
            matchedRoute = "DashboardRoute.\(route)"
        } else if let route = FormsRoute.fromURL(path: path, query: [:]) {
            matchedRoute = "FormsRoute.\(route)"
        } else if let route = SettingsRoute.fromURL(path: path, query: [:]) {
            matchedRoute = "SettingsRoute.\(route)"
        } else {
            matchedRoute = nil
        }
    }
}

// MARK: - Design Tokens Catalog View
struct DesignTokensCatalogView: View {
    @Environment(\.designTokens) var tokens

    var body: some View {
        List {
            Section("Colors") {
                ColorRow(name: "Primary", color: tokens.colors.primary)
                ColorRow(name: "Secondary", color: tokens.colors.secondary)
                ColorRow(name: "Error", color: tokens.colors.error)
                ColorRow(name: "Warning", color: tokens.colors.warning)
                ColorRow(name: "Success", color: tokens.colors.success)
            }

            Section("Typography") {
                TypographyRow(name: "Large Title", font: tokens.typography.largeTitle)
                TypographyRow(name: "Title 1", font: tokens.typography.title1)
                TypographyRow(name: "Headline", font: tokens.typography.headline)
                TypographyRow(name: "Body", font: tokens.typography.body)
                TypographyRow(name: "Caption", font: tokens.typography.caption1)
            }

            Section("Spacing") {
                SpacingRow(name: "xxSmall", value: tokens.spacing.xxSmall)
                SpacingRow(name: "xSmall", value: tokens.spacing.xSmall)
                SpacingRow(name: "small", value: tokens.spacing.small)
                SpacingRow(name: "medium", value: tokens.spacing.medium)
                SpacingRow(name: "large", value: tokens.spacing.large)
                SpacingRow(name: "xLarge", value: tokens.spacing.xLarge)
                SpacingRow(name: "xxLarge", value: tokens.spacing.xxLarge)
            }

            Section("Corner Radius") {
                SpacingRow(name: "small", value: tokens.cornerRadius.small)
                SpacingRow(name: "medium", value: tokens.cornerRadius.medium)
                SpacingRow(name: "large", value: tokens.cornerRadius.large)
            }
        }
        .navigationTitle("Design Tokens")
    }
}

private struct ColorRow: View {
    let name: String
    let color: Color

    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(width: 32, height: 32)

            Text(name)

            Spacer()

            Text("tokens.colors.\(name.lowercased())")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}

private struct TypographyRow: View {
    let name: String
    let font: Font

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(font)

            Text("tokens.typography.\(name.lowercased().replacingOccurrences(of: " ", with: ""))")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct SpacingRow: View {
    let name: String
    let value: CGFloat

    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: value, height: 16)

            Text(name)

            Spacer()

            Text("\(Int(value))pt")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Profile View
struct ProfileView: View {
    var body: some View {
        VStack {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 100))
                .foregroundStyle(.quaternary)
                .padding()

            Text("Demo User")
                .font(.title)
                .fontWeight(.bold)

            Text("demo@archery.app")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Task Detail View
struct TaskDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Task Details")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.horizontal)

                Text("This view would show detailed task information.")
                    .padding(.horizontal)
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Onboarding Flow
struct OnboardingFlow: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack {
            TabView {
                OnboardingPage(
                    title: "Welcome to Archery",
                    subtitle: "Macro-powered SwiftUI Architecture",
                    systemImage: "target"
                )

                OnboardingPage(
                    title: "Powerful Macros",
                    subtitle: "Generate boilerplate code automatically",
                    systemImage: "wand.and.stars"
                )

                OnboardingPage(
                    title: "Type-Safe",
                    subtitle: "Strongly typed, testable architecture",
                    systemImage: "checkmark.shield"
                )
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button("Get Started") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
}

struct OnboardingPage: View {
    let title: String
    let subtitle: String
    let systemImage: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: systemImage)
                .font(.system(size: 80))
                .foregroundStyle(Color.accentColor)
            
            Text(title)
                .font(.title)
                .fontWeight(.bold)
            
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

// MARK: - Subscription View
struct SubscriptionView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Premium Features")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                FeatureRow(
                    icon: "infinity",
                    title: "Unlimited Tasks",
                    description: "Create as many tasks as you need"
                )

                FeatureRow(
                    icon: "person.3",
                    title: "Team Collaboration",
                    description: "Work together with your team"
                )

                FeatureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Advanced Analytics",
                    description: "Detailed insights and reports"
                )

                Button("Subscribe Now") {
                    // Handle subscription
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Sign Up View
struct SignUpView: View {
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var name = ""

    var body: some View {
        VStack(spacing: 20) {
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .autocapitalization(.none)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.newPassword)

            SecureField("Confirm Password", text: $confirmPassword)
                .textFieldStyle(.roundedBorder)
                .textContentType(.newPassword)

            Button("Create Account") {
                // Handle sign up
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding()
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Forgot Password View
struct ForgotPasswordView: View {
    @Environment(\.dismiss) var dismiss
    @State private var email = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Enter your email address and we'll send you a link to reset your password.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .autocapitalization(.none)

            Button("Send Reset Link") {
                // Handle password reset
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding()
        .navigationTitle("Reset Password")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
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
        Form {
            Section("Task Details") {
                TextField("Title", text: $title)

                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Options") {
                Picker("Priority", selection: $priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Label(priority.title, systemImage: priority.icon)
                            .tag(priority)
                    }
                }

                Toggle("Set Due Date", isOn: $hasDueDate)

                if hasDueDate {
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                }
            }
        }
        .navigationTitle("New Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    // Save task
                    dismiss()
                }
                .disabled(title.isEmpty)
            }
        }
    }
}
