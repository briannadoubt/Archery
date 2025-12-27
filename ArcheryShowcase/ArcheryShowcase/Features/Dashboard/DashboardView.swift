import SwiftUI
import Archery
#if canImport(AppIntents)
import AppIntents
#endif

// MARK: - Dashboard View

struct DashboardView: View {
    @Query(\.byCreatedAt)
    var allTasks: [TaskItem]

    @Query(\.all)
    var allProjects: [PersistentProject]

    @Environment(\.databaseWriter) private var writer
    @Environment(\.navigationHandle) private var nav

    @State private var showSiriTip = true

    // Direct filtering on TaskItem (no conversion needed!)
    var completedTasks: [TaskItem] { allTasks.filter { $0.status == .completed } }
    var inProgressTasks: [TaskItem] { allTasks.filter { $0.status == .inProgress } }
    var overdueTasks: [TaskItem] { allTasks.filter { ($0.dueDate ?? .distantFuture) < Date() && !$0.isCompleted } }
    var recentTasks: [TaskItem] { Array(allTasks.filter { !$0.isCompleted }.prefix(5)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                WelcomeHeaderView(taskCount: allTasks.count, completedToday: completedTasks.count)
                    .padding(.horizontal)

                // Siri tip for listing tasks - uses macro-generated intent
                #if canImport(AppIntents)
                SiriTipView(intent: TaskItemEntityListIntent(), isVisible: $showSiriTip)
                    .padding(.horizontal)
                #endif

                // Weather widget using @APIClient
                WeatherWidget(location: "San Francisco")
                    .padding(.horizontal)

                NavigationStatsView(
                    total: allTasks.count,
                    completed: completedTasks.count,
                    inProgress: inProgressTasks.count,
                    overdue: overdueTasks.count,
                    projects: allProjects.count
                )
                .padding(.horizontal)

                ActivityChartView(tasks: allTasks)
                    .frame(height: 200)
                    .padding(.horizontal)

                InteractiveRecentTasksView(
                    tasks: recentTasks,
                    onToggleComplete: { task in Task { await toggleTaskCompletion(task) } },
                    onDelete: { task in Task { await deleteTask(task) } },
                    onTap: { task in nav?.navigate(to: DashboardRoute.editTask(id: task.id), style: .sheet()) }
                )

                NavigationQuickActionsView()
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { nav?.navigate(to: SettingsRoute.account, style: .sheet()) } label: {
                    Image(systemName: "person.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { nav?.navigate(to: DashboardRoute.notifications, style: .sheet()) } label: {
                    Image(systemName: "bell")
                }
            }
        }
    }

    private func toggleTaskCompletion(_ task: TaskItem) async {
        guard let writer else { return }
        var updated = task
        updated.status = task.isCompleted ? .todo : .completed
        _ = try? await writer.update(updated)
    }

    private func deleteTask(_ task: TaskItem) async {
        guard let writer else { return }
        _ = try? await writer.delete(TaskItem.self, id: task.id)
    }
}

// MARK: - Filtered Task List View

struct FilteredTaskListView: View {
    let filter: TaskFilter
    let title: String

    @Query(\.byCreatedAt)
    var allTasks: [TaskItem]

    @Environment(\.databaseWriter) private var writer
    @Environment(\.dismiss) private var dismiss

    // Direct filtering on TaskItem (no conversion needed!)
    var filteredTasks: [TaskItem] {
        switch filter {
        case .all: return allTasks
        case .completed: return allTasks.filter { $0.isCompleted }
        case .incomplete: return allTasks.filter { !$0.isCompleted }
        case .high: return allTasks.filter { $0.priority == .high || $0.priority == .urgent }
        case .today: return allTasks.filter { Calendar.current.isDateInToday($0.dueDate ?? .distantPast) }
        case .upcoming:
            return allTasks.filter {
                guard let dueDate = $0.dueDate else { return false }
                return dueDate > Date() && !Calendar.current.isDateInToday(dueDate)
            }
        }
    }

    var body: some View {
        List {
            ForEach(filteredTasks) { task in
                TaskRowView(task: task)
                    .swipeActions(edge: .leading) {
                        Button { Task { await toggleComplete(task) } } label: {
                            Label(task.isCompleted ? "Undo" : "Done", systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
                        }
                        .tint(task.isCompleted ? .gray : .green)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { Task { await delete(task) } } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .overlay {
            if filteredTasks.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "checkmark.circle", description: Text("No tasks match this filter"))
            }
        }
    }

    private func toggleComplete(_ task: TaskItem) async {
        guard let writer else { return }
        var updated = task
        updated.status = task.isCompleted ? .todo : .completed
        _ = try? await writer.update(updated)
    }

    private func delete(_ task: TaskItem) async {
        guard let writer else { return }
        _ = try? await writer.delete(TaskItem.self, id: task.id)
    }
}

// TaskRowView is defined in TaskListView.swift
