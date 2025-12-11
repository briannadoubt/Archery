import SwiftUI
import Archery

// MARK: - Dashboard View

struct DashboardView: View {
    @Query(PersistentTask.all().order(by: PersistentTask.Columns.createdAt, ascending: false))
    var allTasks: [PersistentTask]

    @Query(PersistentProject.all())
    var allProjects: [PersistentProject]

    @Environment(\.databaseWriter) private var writer
    @Environment(\.navigationHandle) private var nav

    var taskItems: [TaskItem] { allTasks.map { $0.toTaskItem() } }
    var completedTasks: [TaskItem] { taskItems.filter { $0.status == .completed } }
    var inProgressTasks: [TaskItem] { taskItems.filter { $0.status == .inProgress } }
    var overdueTasks: [TaskItem] { taskItems.filter { ($0.dueDate ?? .distantFuture) < Date() && !$0.isCompleted } }
    var recentTaskItems: [TaskItem] { Array(taskItems.filter { !$0.isCompleted }.prefix(5)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                WelcomeHeaderView(taskCount: taskItems.count, completedToday: completedTasks.count)
                    .padding(.horizontal)

                NavigationStatsView(
                    total: taskItems.count,
                    completed: completedTasks.count,
                    inProgress: inProgressTasks.count,
                    overdue: overdueTasks.count,
                    projects: allProjects.count
                )
                .padding(.horizontal)

                ActivityChartView(tasks: taskItems)
                    .frame(height: 200)
                    .padding(.horizontal)

                InteractiveRecentTasksView(
                    tasks: recentTaskItems,
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { nav?.navigate(to: SettingsRoute.account, style: .sheet()) } label: {
                    Image(systemName: "person.circle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { nav?.navigate(to: DashboardRoute.notifications, style: .sheet()) } label: {
                    Image(systemName: "bell")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showNewTaskSheet)) { _ in
            nav?.navigate(to: DashboardRoute.newTask, style: .sheet())
        }
    }

    private func toggleTaskCompletion(_ task: TaskItem) async {
        guard let writer else { return }
        let newStatus: TaskStatus = task.isCompleted ? .todo : .completed
        let updated = TaskItem(
            id: task.id, title: task.title, description: task.description,
            status: newStatus, priority: task.priority, dueDate: task.dueDate,
            tags: task.tags, projectId: task.projectId, createdAt: task.createdAt
        )
        _ = try? await writer.update(PersistentTask(from: updated))
    }

    private func deleteTask(_ task: TaskItem) async {
        guard let writer else { return }
        _ = try? await writer.delete(PersistentTask.self, id: task.id)
    }
}

// MARK: - Filtered Task List View

struct FilteredTaskListView: View {
    let filter: TaskFilter
    let title: String

    @Query(PersistentTask.all().order(by: PersistentTask.Columns.createdAt, ascending: false))
    var allTasks: [PersistentTask]

    @Environment(\.databaseWriter) private var writer
    @Environment(\.dismiss) private var dismiss

    var filteredTasks: [TaskItem] {
        let tasks = allTasks.map { $0.toTaskItem() }
        switch filter {
        case .all: return tasks
        case .completed: return tasks.filter { $0.isCompleted }
        case .incomplete: return tasks.filter { !$0.isCompleted }
        case .high: return tasks.filter { $0.priority == .high || $0.priority == .urgent }
        case .today: return tasks.filter { Calendar.current.isDateInToday($0.dueDate ?? .distantPast) }
        case .upcoming:
            return tasks.filter {
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
        let newStatus: TaskStatus = task.isCompleted ? .todo : .completed
        let updated = TaskItem(
            id: task.id, title: task.title, description: task.description,
            status: newStatus, priority: task.priority, dueDate: task.dueDate,
            tags: task.tags, projectId: task.projectId, createdAt: task.createdAt
        )
        _ = try? await writer.update(PersistentTask(from: updated))
    }

    private func delete(_ task: TaskItem) async {
        guard let writer else { return }
        _ = try? await writer.delete(PersistentTask.self, id: task.id)
    }
}

// TaskRowView is defined in TaskListView.swift
