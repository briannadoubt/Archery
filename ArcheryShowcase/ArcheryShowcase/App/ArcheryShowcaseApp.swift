import SwiftUI
import Archery
import GRDB

// MARK: - @Route Demos (for NavigationMacroDemo showcase)
//
// These demonstrate the @Route macro with @requires for entitlement gating.
// They're used by NavigationMacroDemo.swift to show live entitlement checking.

@Route(path: "tasks")
enum TasksRoute: NavigationRoute {
    case root
    case detail(id: String)

    @presents(.sheet)
    case newTask

    @presents(.sheet, detents: [.large])
    case taskWizard

    @requires(.premium)
    @presents(.fullScreen)
    case analytics

    @requires(.pro)
    @presents(.sheet, detents: [.large])
    case bulkEdit
}

@Route(path: "insights", requires: .premium)
enum InsightsRoute: NavigationRoute {
    case root
    case reports
    case export
}

@Route(path: "admin", requires: .pro)
enum AdminRoute: NavigationRoute {
    case root
    case users
    case permissions
}

@Route(path: "dashboard")
enum DashboardRoute: NavigationRoute {
    case root
    case stats
    case activity

    @presents(.sheet, detents: [.medium, .large])
    case notifications

    @presents(.sheet)
    case newTask

    @presents(.sheet, detents: [.large])
    case filteredTasks(filter: TaskFilter)

    @presents(.sheet)
    case editTask(id: String)
}

@Route(path: "forms")
enum FormsRoute: NavigationRoute {
    case root
    case validation
    case builder
}

@Route(path: "settings")
enum SettingsRoute: NavigationRoute {
    case root
    case account
    case appearance
    case about

    @presents(.sheet, detents: [.large])
    case paywall

    @presents(.sheet, detents: [.large])
    case premiumPaywall
}

// MARK: - @Flow Demo: Task Creation Wizard
//
// This demonstrates the @Flow macro which generates:
// - NavigationFlow conformance
// - Step management (steps array)
// - Flow configuration with branches and skips
// - Deep link support (/flow/taskCreation/step/2)

@Flow(path: "taskCreation", persists: false)
enum TaskCreationFlow: CaseIterable, Hashable {
    case basicInfo      // Step 1: Title and description
    case scheduling     // Step 2: Due date and reminders
    case priority       // Step 3: Priority and tags
    case review         // Step 4: Review and confirm
}

// MARK: - Main App with @AppShell
//
// @AppShell generates:
// - ShellView with TabView navigation and per-tab NavigationStacks
// - Entitlement-gated tabs via @requires
// - App body with database loading/error states
// - StateObjects for theme, store, and database
// - Init with appearance configuration
// - Analytics auto-tracking for navigation, repository, monetization, auth, errors

@AppShell
@main
struct ArcheryShowcaseApp: App {
    // MARK: - Tabs with Entitlement Gating

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

    // MARK: - Configuration (discovered by @AppShell)

    /// Database for GRDB persistence (auto-wired to ShellView)
    static var database: AppDatabase { .shared }

    /// Theme manager for appearance (auto-injected as environment object)
    static var themeManager: ThemeManager { ThemeManager() }

    /// Analytics providers (auto-configured with framework event bridging)
    static var analyticsProviders: [AnalyticsProvider] {
        #if DEBUG
        [DebugAnalyticsProvider()]
        #else
        [DebugAnalyticsProvider()]
        #endif
    }

    // MARK: - Tab Content Builders
    //
    // Note: Use file-scope route types (DashboardRoute, TasksRoute, etc.)
    // not ShellView-prefixed types. The @AppShell macro detects these builders
    // and uses the external @Route-decorated types directly for deep link support.

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
        case .detail(let id): Text("Task Detail: \(id)").navigationTitle("Task")
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
        case .about: Text("About Archery Showcase").navigationTitle("About")
        case .paywall: PaywallView()
        case .premiumPaywall: PaywallView(configuration: .premium)
        }
    }
}

// MARK: - Tab Content Views

struct InsightsTabContent: View {
    var body: some View {
        List {
            Section("Premium Insights") {
                NavigationLink {
                    Text("Weekly Summary").navigationTitle("Weekly")
                } label: {
                    Label("Weekly Summary", systemImage: "chart.bar")
                }
                NavigationLink {
                    Text("Trend Analysis").navigationTitle("Trends")
                } label: {
                    Label("Trend Analysis", systemImage: "chart.line.uptrend.xyaxis")
                }
                NavigationLink {
                    Text("Productivity Score").navigationTitle("Score")
                } label: {
                    Label("Productivity Score", systemImage: "gauge")
                }
            }

            Section("Reports") {
                NavigationLink {
                    Text("Export Reports").navigationTitle("Export")
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle("Insights")
    }
}

struct AdminTabContent: View {
    var body: some View {
        List {
            Section("Administration") {
                NavigationLink {
                    Text("User Management").navigationTitle("Users")
                } label: {
                    Label("Users", systemImage: "person.3")
                }
                NavigationLink {
                    Text("Permissions").navigationTitle("Permissions")
                } label: {
                    Label("Permissions", systemImage: "lock.shield")
                }
                NavigationLink {
                    Text("Audit Log").navigationTitle("Audit")
                } label: {
                    Label("Audit Log", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        .navigationTitle("Admin")
    }
}

// MARK: - Route Destination Views (for routes without existing views)

struct TaskAnalyticsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Task Analytics")
                .font(.largeTitle)

            Text("Premium feature - requires .premium entitlement")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Analytics")
    }
}

struct TaskBulkEditView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Bulk Edit")
                .font(.largeTitle)

            Text("Pro feature - requires .pro entitlement")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Bulk Edit")
    }
}

// MARK: - Dashboard Route Destination Views

struct DashboardStatsView: View {
    @GRDBQuery(PersistentTask.all()) var allTasks: [PersistentTask]
    @GRDBQuery(PersistentProject.all()) var allProjects: [PersistentProject]

    var body: some View {
        List {
            Section("Task Statistics") {
                StatRow(label: "Total Tasks", value: "\(allTasks.count)", icon: "checklist", color: .blue)
                StatRow(label: "Completed", value: "\(allTasks.filter { $0.status == TaskStatus.completed.rawValue }.count)", icon: "checkmark.circle.fill", color: .green)
                StatRow(label: "In Progress", value: "\(allTasks.filter { $0.status == TaskStatus.inProgress.rawValue }.count)", icon: "clock.fill", color: .orange)
                StatRow(label: "Overdue", value: "\(allTasks.filter { ($0.dueDate ?? .distantFuture) < Date() && $0.status != TaskStatus.completed.rawValue }.count)", icon: "exclamationmark.triangle.fill", color: .red)
            }

            Section("Projects") {
                StatRow(label: "Total Projects", value: "\(allProjects.count)", icon: "folder.fill", color: .purple)
            }
        }
        .navigationTitle("Statistics")
    }
}

struct StatRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 30)
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }
}

struct DashboardActivityView: View {
    @GRDBQuery(PersistentTask.all().order(by: PersistentTask.Columns.createdAt, ascending: false).limit(20))
    var recentTasks: [PersistentTask]

    var body: some View {
        List {
            Section("Recent Activity") {
                ForEach(recentTasks) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .fontWeight(.medium)
                        HStack {
                            Text(task.status.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(task.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Activity")
    }
}

// MARK: - Task Edit Wrapper (fetches task by ID)

struct TaskEditWrapper: View {
    let taskId: String
    @GRDBQuery(PersistentTask.all()) var tasks: [PersistentTask]

    var task: PersistentTask? {
        tasks.first { $0.id == taskId }
    }

    var body: some View {
        if let task {
            TaskEditView(task: task.toTaskItem())
        } else {
            ContentUnavailableView("Task Not Found", systemImage: "doc.questionmark")
        }
    }
}

// MARK: - Task Edit View (Coordinator-compatible)

struct TaskEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.grdbWriter) private var writer

    let task: TaskItem

    @State private var title: String
    @State private var description: String
    @State private var priority: TaskPriority
    @State private var status: TaskStatus
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var showDeleteConfirmation = false

    init(task: TaskItem) {
        self.task = task
        _title = State(initialValue: task.title)
        _description = State(initialValue: task.description ?? "")
        _priority = State(initialValue: task.priority)
        _status = State(initialValue: task.status)
        _hasDueDate = State(initialValue: task.dueDate != nil)
        _dueDate = State(initialValue: task.dueDate ?? Date())
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Title", text: $title)
                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Status") {
                Picker("Status", selection: $status) {
                    Label("To Do", systemImage: "circle").tag(TaskStatus.todo)
                    Label("In Progress", systemImage: "clock").tag(TaskStatus.inProgress)
                    Label("Completed", systemImage: "checkmark.circle.fill").tag(TaskStatus.completed)
                    Label("Archived", systemImage: "archivebox").tag(TaskStatus.archived)
                }
            }

            Section("Priority") {
                Picker("Priority", selection: $priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { p in
                        Label(p.title, systemImage: p.icon)
                            .foregroundStyle(p.color)
                            .tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Due Date") {
                Toggle("Set due date", isOn: $hasDueDate.animation())
                if hasDueDate {
                    DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Task", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Edit Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveTask() }
                    .disabled(title.isEmpty)
            }
        }
        .confirmationDialog("Delete Task?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteTask() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func saveTask() {
        let updated = TaskItem(
            id: task.id,
            title: title,
            description: description.isEmpty ? nil : description,
            status: status,
            priority: priority,
            dueDate: hasDueDate ? dueDate : nil,
            tags: task.tags,
            projectId: task.projectId,
            createdAt: task.createdAt
        )
        Task {
            guard let writer else { return }
            try? await writer.update(PersistentTask(from: updated))
        }
        dismiss()
    }

    private func deleteTask() {
        Task {
            guard let writer else { return }
            _ = try? await writer.delete(PersistentTask.self, id: task.id)
        }
        dismiss()
    }
}

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                NotificationRow(
                    title: "Task Due Soon",
                    message: "Complete project proposal by tomorrow",
                    icon: "clock.badge.exclamationmark",
                    color: .orange,
                    time: "2h ago"
                )
                NotificationRow(
                    title: "Task Completed",
                    message: "Design review has been marked as done",
                    icon: "checkmark.circle.fill",
                    color: .green,
                    time: "5h ago"
                )
                NotificationRow(
                    title: "New Comment",
                    message: "Alex commented on your task",
                    icon: "bubble.left.fill",
                    color: .blue,
                    time: "1d ago"
                )
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

struct NotificationRow: View {
    let title: String
    let message: String
    let icon: String
    let color: Color
    let time: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
