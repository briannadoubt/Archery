import SwiftUI
import Archery

// MARK: - Main App
//
// @AppShell auto-generates:
// - App body with database loading/error states
// - StateObjects for theme, store, database
// - Init with appearance configuration
// - ShellView with TabView navigation
// - Analytics auto-tracking
//
// The `schema:` parameter lists @Persistable types that need database tables.
// The macro auto-generates:
// - GeneratedAppDatabase class with @Observable
// - MigrationRegistry.register() for each type
// - QuerySourceRegistry registration for types with Sources

@AppShell(schema: [TaskItem.self, PersistentProject.self])
@main
struct ArcheryShowcaseApp: App {
    // MARK: - Tabs

    enum Tab: CaseIterable {
        case dashboard
        case tasks

        @requires(.premium, behavior: .locked)
        case insights

        @requires(.pro, behavior: .hidden)
        case admin

        case settings
    }

    // MARK: - Additional Windows (macOS, iPadOS, visionOS)
    //
    // The @Window macro creates additional WindowGroup scenes
    // that can be opened via Environment's openWindow action.

    #if os(macOS) || os(iOS) || os(visionOS)
    enum Window: CaseIterable {
        case preferences
        case macroExplorer
        case quickEntry
    }
    #endif

    // MARK: - Configuration

    static var themeManager: ThemeManager { ThemeManager() }
    static var analyticsProviders: [AnalyticsProvider] { [DebugAnalyticsProvider()] }

    // MARK: - App Configuration Setup
    //
    // Sets up the @Configuration system with remote config and demo secrets.
    // Called during app startup to initialize configuration before first use.

    static func setupConfiguration() async {
        // Setup remote config if URL is provided
        if let urlString = AppConfiguration.featureFlagsURL,
           let url = URL(string: urlString) {
            AppConfiguration.setupRemoteConfig(
                url: url,
                refreshInterval: TimeInterval(AppConfiguration.remoteConfigInterval)
            )
        }

        // Store demo secrets for showcase purposes
        #if DEBUG
        await setupDemoSecrets()
        #endif
    }

    #if DEBUG
    private static func setupDemoSecrets() async {
        // Store demo secrets to demonstrate @Secret property resolution
        let demoSecrets = [
            Secret(
                key: "apiKey",
                value: "demo-api-key-ARCHERY-12345",
                environment: ConfigurationEnvironment.current,
                tags: ["demo", "api"]
            ),
            Secret(
                key: "analyticsTrackingId",
                value: "UA-DEMO-ARCHERY-67890",
                environment: ConfigurationEnvironment.current,
                tags: ["demo", "analytics"]
            )
        ]

        for secret in demoSecrets {
            try? SecretsManager.shared.store(secret)
        }
    }
    #endif

    // MARK: - Database Seeding Hook
    //
    // If this function exists, @AppShell calls it during database setup.
    // It's called after migrations run, to seed initial data if needed.

    static func seedDemoData(container: PersistenceContainer) async throws {
        // Setup configuration and demo secrets
        await setupConfiguration()

        // Only seed if database is empty
        let taskCount = try await container.read { db in
            try TaskItem.fetchCount(db)
        }
        guard taskCount == 0 else { return }

        try await container.write { db in
            // Seed projects
            let projects = [
                PersistentProject(id: "proj-1", name: "Mobile App", projectDescription: "iOS and Android development", color: "blue", icon: "iphone"),
                PersistentProject(id: "proj-2", name: "Backend API", projectDescription: "Server infrastructure", color: "green", icon: "server.rack"),
                PersistentProject(id: "proj-3", name: "Design System", projectDescription: "UI/UX components", color: "purple", icon: "paintbrush"),
            ]
            for project in projects {
                try project.insert(db)
            }

            // Seed tasks
            let tasks = [
                TaskItem(id: "task-1", title: "Review pull request", taskDescription: "Check the latest changes for the auth module", status: .inProgress, priority: .high, dueDate: Date().addingTimeInterval(3600), tags: ["code-review", "urgent"], projectId: "proj-1"),
                TaskItem(id: "task-2", title: "Update API documentation", taskDescription: "Add examples for new endpoints", status: .todo, priority: .medium, dueDate: Date().addingTimeInterval(86400), tags: ["docs"], projectId: "proj-2"),
                TaskItem(id: "task-3", title: "Fix login bug", taskDescription: "Handle edge case for social login timeout", status: .todo, priority: .urgent, dueDate: Date(), tags: ["bug", "auth"], projectId: "proj-1"),
                TaskItem(id: "task-4", title: "Design system audit", taskDescription: "Review color tokens for accessibility", status: .inProgress, priority: .medium, tags: ["design", "a11y"], projectId: "proj-3"),
                TaskItem(id: "task-5", title: "Weekly team sync", taskDescription: "Sprint planning meeting", status: .completed, priority: .low, dueDate: Date().addingTimeInterval(-86400), tags: ["meeting"]),
                TaskItem(id: "task-6", title: "Performance optimization", taskDescription: "Improve app launch time by 30%", status: .todo, priority: .high, dueDate: Date().addingTimeInterval(172800), tags: ["performance"], projectId: "proj-1"),
                TaskItem(id: "task-7", title: "Write unit tests", taskDescription: "Increase code coverage to 80%", status: .todo, priority: .medium, dueDate: Date().addingTimeInterval(259200), tags: ["testing"], projectId: "proj-2"),
                TaskItem(id: "task-8", title: "Setup CI/CD pipeline", taskDescription: "Automate deployment process", status: .completed, priority: .high, tags: ["devops"], projectId: "proj-2"),
            ]
            for task in tasks {
                try task.insert(db)
            }
        }
    }

    // MARK: - Tab Builders

    @MainActor @ViewBuilder
    static func buildDashboard(_ route: DashboardRoute, _ container: EnvContainer) -> some View {
        switch route {
        case .root: DashboardView()
        case .stats: DashboardStatsView()
        case .activity: DashboardActivityView()
        case .notifications: NotificationsView()
        case .newTask: NewTaskSheet()
        case .filteredTasks(let filter): FilteredTaskListView(filter: filter, title: filter.title)
        case .editTask(let id): TaskEditView(taskId: id)
        }
    }

    @MainActor @ViewBuilder
    static func buildTasks(_ route: TasksRoute, _ container: EnvContainer) -> some View {
        switch route {
        case .root: TaskListView()
        case .detail(let id): TaskDetailView(taskId: id)
        case .newTask: TaskCreationView()
        case .taskWizard: TaskCreationView()
        case .analytics: TaskAnalyticsView()
        case .bulkEdit: TaskBulkEditView()
        case .advancedFilters: AdvancedFiltersView()
        case .auditLog: AuditLogView()
        }
    }

    @MainActor @ViewBuilder
    static func buildInsights(_ route: InsightsRoute, _ container: EnvContainer) -> some View {
        switch route {
        case .root: InsightsTabContent()
        case .reports: Text("Reports").navigationTitle("Reports")
        case .export: Text("Export").navigationTitle("Export")
        }
    }

    @MainActor @ViewBuilder
    static func buildAdmin(_ route: AdminRoute, _ container: EnvContainer) -> some View {
        switch route {
        case .root: AdminTabContent()
        case .users: Text("Users").navigationTitle("Users")
        case .permissions: Text("Permissions").navigationTitle("Permissions")
        case .userManagement: UserManagementView()
        case .securitySettings: SecuritySettingsView()
        case .moderationQueue: ModerationQueueView()
        }
    }

    @MainActor @ViewBuilder
    static func buildSettings(_ route: SettingsRoute, _ container: EnvContainer) -> some View {
        switch route {
        case .root: SettingsView()
        case .account: ProfileView()
        case .appearance: AppearanceView()
        case .about: AboutView()
        case .paywall: PaywallView()
        case .premiumPaywall: PaywallView(configuration: .premium)

        // Window routes - presented in separate windows on supported platforms
        // On unsupported platforms, they render as regular views (fallback to push)
        case .preferences:
            #if os(macOS) || os(iOS) || os(visionOS)
            PreferencesWindowView()
            #else
            Text("Preferences").navigationTitle("Preferences")
            #endif
        case .macroExplorer:
            #if os(macOS) || os(iOS) || os(visionOS)
            MacroExplorerWindowView()
            #else
            Text("Macro Explorer").navigationTitle("Macro Explorer")
            #endif
        case .quickEntry:
            #if os(macOS) || os(iOS) || os(visionOS)
            QuickEntryWindowView()
            #else
            Text("Quick Entry").navigationTitle("Quick Entry")
            #endif
        }
    }

    // MARK: - Window Builder (macOS, iPadOS, visionOS)
    //
    // Window builder returns a Scene for the given window case.
    // The @AppShell macro generates ShellScenes that calls this for each case.
    // Returns `any Scene` for type erasure since each case returns a different Scene type.

    #if os(macOS) || os(iOS) || os(visionOS)
    @MainActor
    static func buildWindow(_ window: Window, _ container: EnvContainer) -> any Scene {
        switch window {
        case .preferences:
            #if os(macOS)
            return WindowGroup("Preferences", id: "preferences") {
                PreferencesWindowView()
            }
            .windowResizability(.contentSize)
            .defaultSize(width: 500, height: 400)
            #else
            return WindowGroup("Preferences", id: "preferences") {
                PreferencesWindowView()
            }
            #endif

        case .macroExplorer:
            #if os(macOS)
            return WindowGroup("Macro Explorer", id: "macro-explorer") {
                MacroExplorerWindowView()
            }
            .defaultSize(width: 800, height: 600)
            #else
            return WindowGroup("Macro Explorer", id: "macro-explorer") {
                MacroExplorerWindowView()
            }
            #endif

        case .quickEntry:
            #if os(macOS)
            return WindowGroup("Quick Entry", id: "quick-entry") {
                QuickEntryWindowView()
            }
            .windowResizability(.contentSize)
            .defaultSize(width: 400, height: 200)
            #else
            return WindowGroup("Quick Entry", id: "quick-entry") {
                QuickEntryWindowView()
            }
            #endif
        }
    }
    #endif
}

// MARK: - Simple Placeholder Views

struct AboutView: View {
    var body: some View {
        Text("About Archery Showcase")
            .navigationTitle("About")
    }
}

// MARK: - @requiresAny/@requiresAll Demo Views

struct AdvancedFiltersView: View {
    var body: some View {
        List {
            Section {
                Text("This view requires @requiresAny(.premium, .pro)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Filter Options") {
                Toggle("Show Completed", isOn: .constant(false))
                Toggle("High Priority Only", isOn: .constant(true))
                Picker("Date Range", selection: .constant("week")) {
                    Text("Today").tag("today")
                    Text("This Week").tag("week")
                    Text("This Month").tag("month")
                }
            }
        }
        .navigationTitle("Advanced Filters")
    }
}

struct AuditLogView: View {
    var body: some View {
        List {
            Section {
                Text("This view requires @requiresAll(.admin, .verified)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Only admins with verified status can access")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Section("Recent Activity") {
                ForEach(0..<5) { i in
                    HStack {
                        Image(systemName: "person.fill")
                        VStack(alignment: .leading) {
                            Text("User action \(i + 1)")
                            Text("2 hours ago")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Audit Log")
    }
}

struct UserManagementView: View {
    var body: some View {
        List {
            Section {
                Text("This view requires @requiresAny(.admin, .moderator, .support)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Users") {
                ForEach(["Alice", "Bob", "Charlie"], id: \.self) { name in
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                        Text(name)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("User Management")
    }
}

struct SecuritySettingsView: View {
    var body: some View {
        List {
            Section {
                Text("This view requires @requiresAll(.admin, .twoFactorEnabled)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Requires admin role AND 2FA enabled")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Section("Security Options") {
                Toggle("Force 2FA for all users", isOn: .constant(true))
                Toggle("Require email verification", isOn: .constant(true))
                Toggle("Session timeout (15 min)", isOn: .constant(false))
            }
        }
        .navigationTitle("Security Settings")
    }
}

struct ModerationQueueView: View {
    var body: some View {
        List {
            Section {
                Text("This view requires @requiresAll(.moderator, .verified)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pending Items") {
                ForEach(0..<3) { i in
                    HStack {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading) {
                            Text("Flagged content \(i + 1)")
                            Text("Reported 1 hour ago")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Review") {}
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
            }
        }
        .navigationTitle("Moderation Queue")
    }
}

// MARK: - Window Views (macOS, iPadOS, visionOS)

#if os(macOS) || os(iOS) || os(visionOS)

/// Preferences window showing app settings in a separate window
struct PreferencesWindowView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPreferencesView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)

            AppearancePreferencesView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag(1)

            NotificationPreferencesView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
                .tag(2)

            AdvancedPreferencesView()
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
                .tag(3)
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 350)
        #endif
    }
}

struct GeneralPreferencesView: View {
    @State private var autoSave = true
    @State private var defaultView = "Dashboard"

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Auto-save changes", isOn: $autoSave)
                Picker("Default view", selection: $defaultView) {
                    Text("Dashboard").tag("Dashboard")
                    Text("Tasks").tag("Tasks")
                    Text("Forms").tag("Forms")
                }
            }

            Section("Data") {
                Button("Clear Cache") {}
                Button("Reset to Defaults") {}
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

struct AppearancePreferencesView: View {
    @State private var colorScheme = "System"
    @State private var accentColor = "Blue"

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Color Scheme", selection: $colorScheme) {
                    Text("System").tag("System")
                    Text("Light").tag("Light")
                    Text("Dark").tag("Dark")
                }

                Picker("Accent Color", selection: $accentColor) {
                    Text("Blue").tag("Blue")
                    Text("Purple").tag("Purple")
                    Text("Green").tag("Green")
                    Text("Orange").tag("Orange")
                }
            }

            Section("Typography") {
                Toggle("Use system font", isOn: .constant(true))
                Toggle("Larger text", isOn: .constant(false))
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }
}

struct NotificationPreferencesView: View {
    @State private var enableNotifications = true
    @State private var soundEnabled = true

    var body: some View {
        Form {
            Section("Alerts") {
                Toggle("Enable Notifications", isOn: $enableNotifications)
                Toggle("Play Sound", isOn: $soundEnabled)
                    .disabled(!enableNotifications)
            }

            Section("Categories") {
                Toggle("Task reminders", isOn: .constant(true))
                Toggle("Updates", isOn: .constant(true))
                Toggle("Marketing", isOn: .constant(false))
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
    }
}

struct AdvancedPreferencesView: View {
    @State private var debugMode = false
    @State private var analyticsEnabled = true

    var body: some View {
        Form {
            Section("Developer") {
                Toggle("Debug Mode", isOn: $debugMode)
                Toggle("Analytics", isOn: $analyticsEnabled)
            }

            Section("Danger Zone") {
                Button("Export All Data") {}
                Button("Delete Account") {}
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Advanced")
    }
}

/// Macro Explorer window for browsing and testing Archery macros
struct MacroExplorerWindowView: View {
    @State private var selectedMacro: String? = "@AppShell"

    let macros = [
        "@AppShell",
        "@ObservableViewModel",
        "@Persistable",
        "@Route",
        "@Form",
        "@Window",
        "@ImmersiveSpace",
        "@Settings"
    ]

    var body: some View {
        NavigationSplitView {
            List(macros, id: \.self, selection: $selectedMacro) { macro in
                Label(macro, systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .navigationTitle("Macros")
        } detail: {
            if let macro = selectedMacro {
                MacroDetailView(macroName: macro)
            } else {
                ContentUnavailableView("Select a Macro", systemImage: "curlybraces")
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 400)
        #endif
    }
}

struct MacroDetailView: View {
    let macroName: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(macroName)
                    .font(.largeTitle.bold())

                GroupBox("Description") {
                    Text(macroDescription)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Example Usage") {
                    Text(exampleCode)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Generated Code") {
                    Text("// Generated code preview would appear here...")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle(macroName)
    }

    var macroDescription: String {
        switch macroName {
        case "@AppShell": return "The root macro that generates app shell with TabView navigation, deep linking, and entitlement-gated tabs."
        case "@ObservableViewModel": return "Creates an observable view model with lifecycle management and MainActor isolation."
        case "@Persistable": return "Generates GRDB persistence code including table creation and column mappings."
        case "@Route": return "Defines navigation routes with deep link support and presentation styles."
        case "@Form": return "Generates form validation and field management code."
        case "@Window": return "Creates additional window scenes for multi-window apps on macOS, iPadOS, and visionOS."
        case "@ImmersiveSpace": return "Defines immersive space scenes for visionOS spatial computing experiences."
        case "@Settings": return "Creates the Settings scene accessible via Cmd+, on macOS."
        default: return "No description available."
        }
    }

    var exampleCode: String {
        switch macroName {
        case "@AppShell": return """
            @AppShell
            struct MyApp: App {
                enum Tab: CaseIterable {
                    case home
                    case settings
                }
            }
            """
        case "@Window": return """
            @Window(id: "preferences", title: "Preferences")
            enum PreferencesWindow {
                case general
                case advanced
            }
            """
        default: return "// Example code..."
        }
    }
}

/// Quick Entry window for rapid task creation
struct QuickEntryWindowView: View {
    @State private var taskTitle = ""
    @State private var taskPriority = "Medium"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Quick Task Entry")
                .font(.headline)

            TextField("Task title", text: $taskTitle)
                .textFieldStyle(.roundedBorder)

            Picker("Priority", selection: $taskPriority) {
                Text("Low").tag("Low")
                Text("Medium").tag("Medium")
                Text("High").tag("High")
            }
            .pickerStyle(.segmented)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add Task") {
                    // Would save task here
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(taskTitle.isEmpty)
            }
        }
        .padding()
        #if os(macOS)
        .frame(width: 350, height: 150)
        #endif
    }
}

#endif
