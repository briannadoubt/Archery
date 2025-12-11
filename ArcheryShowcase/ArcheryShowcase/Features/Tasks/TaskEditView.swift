import SwiftUI
import Archery

// MARK: - Task Edit Wrapper (fetches task by ID)

struct TaskEditWrapper: View {
    let taskId: String
    @Query(PersistentTask.all()) var tasks: [PersistentTask]

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

// MARK: - Task Edit View

struct TaskEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.databaseWriter) private var writer

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
