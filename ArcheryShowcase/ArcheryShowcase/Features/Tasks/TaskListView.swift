import SwiftUI
import Archery

// MARK: - Task List View (database-powered)

struct TaskListView: View {
    // Reactive query - automatically updates when database changes
    @Query(\.byCreatedAt)
    var tasks: [TaskItem]

    @Environment(\.databaseWriter) private var writer
    @Environment(\.navigationHandle) private var nav

    // ViewModel using @ObservableViewModel for debounced search
    @State private var viewModel = TaskSearchViewModel()
    @State private var showError: Error?

    // Feature flag: cached to avoid observation loops
    @State private var isCompactMode: Bool = false

    // Filtered tasks computed via ViewModel
    var filteredTasks: [TaskItem] {
        viewModel.filteredTasks
    }

    var body: some View {
        List {
            // Filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TaskFilter.allCases, id: \.self) { filter in
                        FilterChip(
                            title: filter.title,
                            isSelected: viewModel.selectedFilter == filter
                        ) {
                            viewModel.selectedFilter = filter
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .padding(.vertical, 8)

            // Loading state
            if $tasks.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading tasks...")
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }

            // Tasks - uses compact mode when feature flag enabled
            ForEach(filteredTasks) { task in
                Group {
                    if isCompactMode {
                        CompactTaskRowView(task: task)
                    } else {
                        TaskRowView(task: task)
                    }
                }
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
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .searchable(text: $viewModel.searchText, prompt: "Search tasks")
        .navigationTitle("Tasks")
        .onChange(of: tasks) { _, newTasks in
            viewModel.updateTasks(newTasks)
        }
        .onAppear {
            viewModel.updateTasks(tasks)
            viewModel.onAppear()
            isCompactMode = FeatureFlagManager.shared.isEnabled(for: AppFeatureFlags.CompactListViewFlag.self)
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .navigationBarTitleDisplayMode(.large)
        .trackScreen("Tasks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    nav?.navigate(to: TasksRoute.newTask, style: .sheet())
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .overlay {
            if !$tasks.isLoading && filteredTasks.isEmpty {
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

    private func deleteTask(_ task: TaskItem) async {
        guard let writer else { return }
        do {
            _ = try await writer.delete(TaskItem.self, id: task.id)
        } catch {
            showError = error
        }
    }

    private func toggleTaskCompletion(_ task: TaskItem) async {
        guard let writer else { return }
        do {
            var updatedTask = task
            updatedTask.status = task.isCompleted ? .todo : .completed
            try await writer.update(updatedTask)
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

                if let description = task.taskDescription {
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
            let tags = task.decodedTags
            if !tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(tags.prefix(2), id: \.self) { tag in
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

// MARK: - Compact Task Row View (Feature Flag)

/// Condensed task row shown when "Compact List View" feature flag is enabled.
struct CompactTaskRowView: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.isCompleted ? .green : .secondary)
                .font(.body)

            Text(task.title)
                .font(.subheadline)
                .strikethrough(task.isCompleted)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                .lineLimit(1)

            Spacer()

            if task.priority != .medium {
                Image(systemName: task.priority.icon)
                    .font(.caption)
                    .foregroundStyle(task.priority.color)
            }

            if let dueDate = task.dueDate {
                Text(dueDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2)
                    .foregroundStyle(dueDate < Date() ? .red : .secondary)
            }
        }
    }
}

// MARK: - Task Creation View

/// Task creation view using @Form-backed TaskFormData for validation.
struct TaskCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.databaseWriter) private var writer

    var onSave: ((TaskItem) -> Void)?

    // Form data with @Form macro validation
    @State private var formData = TaskFormData()
    @State private var hasDueDate = false
    @State private var showValidationError = false

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $formData.title)

                TextField("Description", text: $formData.taskDescription, axis: .vertical)
                    .lineLimit(3...6)
            } footer: {
                if showValidationError && !formData.canSave {
                    Text("Title is required")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Priority") {
                Picker("Priority", selection: $formData.priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Label(priority.title, systemImage: priority.icon)
                            .tag(priority.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Due Date") {
                Toggle("Set due date", isOn: $hasDueDate.animation())

                if hasDueDate {
                    DatePicker(
                        "Due Date",
                        selection: Binding(
                            get: { formData.dueDate ?? Date() },
                            set: { formData.dueDate = $0 }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }

            Section {
                TextField("Tags (comma separated)", text: $formData.tags)
            } header: {
                Text("Tags")
            } footer: {
                Text("Validated with @Form macro - Title required, max 200 chars")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                .disabled(!formData.canSave)
            }
        }
        .onChange(of: hasDueDate) { _, newValue in
            if !newValue {
                formData.dueDate = nil
            } else if formData.dueDate == nil {
                formData.dueDate = Date()
            }
        }
    }

    private func saveTask() {
        // Validate using @Form-generated method
        guard formData.validate() else {
            showValidationError = true
            return
        }

        // Convert form data to TaskItem
        let task = formData.toTaskItem()

        // If callback provided, use it; otherwise save directly
        if let onSave {
            onSave(task)
            dismiss()
        } else {
            // Save directly to database
            Task {
                guard let writer else {
                    print("[TaskCreationView] ERROR: No database writer available!")
                    return
                }
                do {
                    _ = try await writer.insert(task)
                    print("[TaskCreationView] Task saved successfully: \(task.title)")
                } catch {
                    print("[TaskCreationView] Save error: \(error)")
                }
                await MainActor.run {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    TaskListView()
        .databaseContainer(try! PersistenceContainer.inMemory())
}
