import SwiftUI
import Archery

// MARK: - Task Edit View (using @QueryOne)

/// Task editing view demonstrating @QueryOne property wrapper
///
/// @QueryOne provides fetching + editing in one:
/// - Fetches record by ID with live observation
/// - `$task.title` - Direct bindings to properties (returns Binding<T>?)
/// - `$task.isDirty` - Change tracking
/// - `$task.save()` - Async save to database
/// - `$task.reset()` - Revert to original
/// - `$task.delete()` - Remove from database
struct TaskEditView: View {
    @QueryOne var task: TaskItem?
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    init(taskId: String) {
        _task = QueryOne(TaskItem.find(taskId))
    }

    var body: some View {
        Group {
            if task != nil {
                TaskEditForm(
                    projection: $task,
                    showDeleteConfirmation: $showDeleteConfirmation
                )
            } else if $task.loadState == .loading {
                ProgressView("Loading...")
            } else {
                ContentUnavailableView("Task Not Found", systemImage: "doc.questionmark")
            }
        }
        .navigationTitle("Edit Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    $task.reset()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        try? await $task.save()
                        dismiss()
                    }
                }
                .disabled(task?.title.isEmpty != false || !$task.isDirty)
            }
        }
        .confirmationDialog("Delete Task?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await $task.delete()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
    }
}

// MARK: - Task Edit Form (internal)

private struct TaskEditForm: View {
    let projection: SingleQueryOneProjection<TaskItem>
    @Binding var showDeleteConfirmation: Bool

    // Due date toggle binding
    private var hasDueDate: Binding<Bool> {
        Binding(
            get: { projection.dueDate?.wrappedValue != nil },
            set: { newValue in
                if newValue && projection.dueDate?.wrappedValue == nil {
                    projection.dueDate?.wrappedValue = Date()
                } else if !newValue {
                    projection.dueDate?.wrappedValue = nil
                }
            }
        )
    }

    var body: some View {
        Form {
            if let title = projection.title,
               let description = projection.taskDescription,
               let status = projection.status,
               let priority = projection.priority,
               let dueDate = projection.dueDate {

                Section("Details") {
                    TextField("Title", text: title)
                    TextField("Description", text: description.or(""), axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Status") {
                    Picker("Status", selection: status) {
                        Label("To Do", systemImage: "circle").tag(TaskStatus.todo)
                        Label("In Progress", systemImage: "clock").tag(TaskStatus.inProgress)
                        Label("Completed", systemImage: "checkmark.circle.fill").tag(TaskStatus.completed)
                        Label("Archived", systemImage: "archivebox").tag(TaskStatus.archived)
                    }
                }

                Section("Priority") {
                    Picker("Priority", selection: priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { p in
                            Label(p.title, systemImage: p.icon)
                                .foregroundStyle(p.color)
                                .tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Due Date") {
                    Toggle("Set due date", isOn: hasDueDate.animation())
                    if dueDate.wrappedValue != nil {
                        DatePicker("Due", selection: dueDate.or(Date()), displayedComponents: [.date, .hourAndMinute])
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
        }
    }
}
