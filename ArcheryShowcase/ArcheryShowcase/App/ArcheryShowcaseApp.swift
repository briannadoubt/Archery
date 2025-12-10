import SwiftUI
import Archery
import GRDB

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
