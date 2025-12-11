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

@AppShell
@main
struct ArcheryShowcaseApp: App {
    // MARK: - Tabs

    enum Tab: CaseIterable {
        case dashboard
        case tasks
        case forms

        @requires(.premium, behavior: .locked)
        case insights

        @requires(.pro, behavior: .hidden)
        case admin

        case settings
    }

    // MARK: - Configuration

    static var database: AppDatabase { .shared }
    static var themeManager: ThemeManager { ThemeManager() }
    static var analyticsProviders: [AnalyticsProvider] { [DebugAnalyticsProvider()] }

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
        case .editTask(let id): TaskEditWrapper(taskId: id)
        }
    }

    @MainActor @ViewBuilder
    static func buildTasks(_ route: TasksRoute, _ container: EnvContainer) -> some View {
        switch route {
        case .root: TaskListView()
        case .detail(let id): TaskDetailView(taskId: id)
        case .newTask: TaskCreationView(onSave: { _ in })
        case .taskWizard: TaskCreationFlowHost()
        case .analytics: TaskAnalyticsView()
        case .bulkEdit: TaskBulkEditView()
        case .advancedFilters: AdvancedFiltersView()
        case .auditLog: AuditLogView()
        }
    }

    @MainActor @ViewBuilder
    static func buildForms(_ route: FormsRoute, _ container: EnvContainer) -> some View {
        switch route {
        case .root: FormExamplesView()
        case .validation: Text("Validation Demo").navigationTitle("Validation")
        case .builder: Text("Form Builder").navigationTitle("Builder")
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
        }
    }
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
