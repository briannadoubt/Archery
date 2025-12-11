import SwiftUI
import Archery

// MARK: - Task List View (database-powered)

struct TaskListView: View {
    // Reactive query - automatically updates when database changes
    @Query(PersistentTask.all().order(by: PersistentTask.Columns.createdAt, ascending: false))
    var persistentTasks: [PersistentTask]

    @Environment(\.databaseWriter) private var writer
    @Environment(\.appDatabase) private var database
    @Environment(\.navigationHandle) private var nav

    @State private var searchText = ""
    @State private var selectedFilter: TaskFilter = .all
    @State private var showError: Error?

    // Convert to TaskItem for display and apply filters
    var filteredTasks: [TaskItem] {
        var result = persistentTasks.map { $0.toTaskItem() }

        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .today:
            result = result.filter { Calendar.current.isDateInToday($0.dueDate ?? .distantPast) }
        case .upcoming:
            result = result.filter {
                guard let dueDate = $0.dueDate else { return false }
                return dueDate > Date() && !Calendar.current.isDateInToday(dueDate)
            }
        case .completed:
            result = result.filter { $0.isCompleted }
        case .incomplete:
            result = result.filter { !$0.isCompleted }
        case .high:
            result = result.filter { $0.priority == .high || $0.priority == .urgent }
        }

        // Apply search
        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }

        return result
    }

    var body: some View {
        List {
            // Filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TaskFilter.allCases, id: \.self) { filter in
                        FilterChip(
                            title: filter.title,
                            isSelected: selectedFilter == filter
                        ) {
                            selectedFilter = filter
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .padding(.vertical, 8)

            // Loading state
            if $persistentTasks.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading tasks...")
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }

            // Tasks
            ForEach(filteredTasks) { task in
                TaskRowView(task: task)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await deleteTask(task) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { await toggleTaskCompletion(task) }
                        } label: {
                            Label(
                                task.isCompleted ? "Incomplete" : "Complete",
                                systemImage: task.isCompleted ? "xmark.circle" : "checkmark.circle"
                            )
                        }
                        .tint(task.isCompleted ? .gray : .green)
                    }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search tasks")
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.large)
        .trackScreen("Tasks")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    nav?.navigate(to: TasksRoute.newTask, style: .sheet())
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .overlay {
            if !$persistentTasks.isLoading && filteredTasks.isEmpty {
                ContentUnavailableView(
                    "No Tasks",
                    systemImage: "checklist",
                    description: Text("Create your first task to get started")
                )
            }
        }
        .alert("Error", isPresented: .init(
            get: { showError != nil },
            set: { if !$0 { showError = nil } }
        )) {
            Button("OK") { showError = nil }
        } message: {
            if let error = showError {
                Text(error.localizedDescription)
            }
        }
    }

    // MARK: - Database Operations

    private func createTask(_ task: TaskItem) async {
        guard let writer else { return }
        do {
            let persistentTask = PersistentTask(from: task)
            _ = try await writer.insert(persistentTask)
            // Analytics: entity_created auto-tracked by @DatabaseRepository
        } catch {
            showError = error
            // Analytics: error_occurred auto-tracked by ArcheryErrorTracker
        }
    }

    private func deleteTask(_ task: TaskItem) async {
        guard let writer else { return }
        do {
            _ = try await writer.delete(PersistentTask.self, id: task.id)
            // Analytics: entity_deleted auto-tracked by @DatabaseRepository
        } catch {
            showError = error
        }
    }

    private func toggleTaskCompletion(_ task: TaskItem) async {
        guard let writer else { return }
        do {
            let newStatus: TaskStatus = task.isCompleted ? .todo : .completed
            let updatedTask = TaskItem(
                id: task.id,
                title: task.title,
                description: task.description,
                status: newStatus,
                priority: task.priority,
                dueDate: task.dueDate,
                tags: task.tags,
                projectId: task.projectId,
                createdAt: task.createdAt
            )
            let persistentTask = PersistentTask(from: updatedTask)
            try await writer.update(persistentTask)
        } catch {
            showError = error
        }
    }
}

// MARK: - Supporting Types

enum TaskFilter: String, CaseIterable, Codable, Identifiable {
    case all = "All"
    case today = "Today"
    case upcoming = "Upcoming"
    case completed = "Completed"
    case incomplete = "Incomplete"
    case high = "High Priority"

    var id: String { rawValue }
    var title: String { rawValue }
}

// FilterChip is defined in CommonViews.swift

// MARK: - Task Row View

struct TaskRowView: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 12) {
            // Completion indicator
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.isCompleted ? .green : .secondary)
                .font(.title3)

            // Task details
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                if let description = task.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if let dueDate = task.dueDate {
                        Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                            .font(.caption2)
                            .foregroundStyle(dueDate < Date() ? .red : .secondary)
                    }

                    if task.priority != .medium {
                        Label(task.priority.title, systemImage: task.priority.icon)
                            .font(.caption2)
                            .foregroundStyle(task.priority.color)
                    }
                }
            }

            Spacer()

            // Tags
            if !task.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(task.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Task Creation View

struct TaskCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.databaseWriter) private var writer

    var onSave: ((TaskItem) -> Void)?

    @State private var title = ""
    @State private var description = ""
    @State private var priority: TaskPriority = .medium
    @State private var dueDate: Date?
    @State private var hasDueDate = false
    @State private var tags = ""

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)

                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Priority") {
                Picker("Priority", selection: $priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Label(priority.title, systemImage: priority.icon)
                            .tag(priority)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Due Date") {
                Toggle("Set due date", isOn: $hasDueDate)

                if hasDueDate {
                    DatePicker(
                        "Due Date",
                        selection: Binding(
                            get: { dueDate ?? Date() },
                            set: { dueDate = $0 }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }

            Section("Tags") {
                TextField("Tags (comma separated)", text: $tags)
            }
        }
        .navigationTitle("New Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveTask()
                }
                .disabled(title.isEmpty)
            }
        }
    }

    private func saveTask() {
        let tagList = tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let task = TaskItem(
            title: title,
            description: description.isEmpty ? nil : description,
            status: .todo,
            priority: priority,
            dueDate: hasDueDate ? dueDate : nil,
            tags: tagList
        )

        // If callback provided, use it; otherwise save directly
        if let onSave {
            onSave(task)
        } else {
            Task {
                guard let writer else { return }
                let persistentTask = PersistentTask(from: task)
                _ = try? await writer.insert(persistentTask)
            }
        }
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    TaskListView()
        .databaseContainer(try! PersistenceContainer.inMemory())
}
