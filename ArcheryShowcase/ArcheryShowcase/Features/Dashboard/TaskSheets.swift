import SwiftUI
import Archery

// MARK: - New Task Sheet

struct NewTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.databaseWriter) private var writer

    @State private var title = ""
    @State private var description = ""
    @State private var priority: TaskPriority = .medium
    @State private var hasDueDate = false
    @State private var dueDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Task Details") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { p in
                            Label(p.title, systemImage: p.icon).tag(p)
                        }
                    }
                }

                Section("Due Date") {
                    Toggle("Set due date", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createTask() }
                        .disabled(title.isEmpty)
                }
            }
        }
    }

    private func createTask() {
        // Create TaskItem directly (no TaskItem conversion needed!)
        let task = TaskItem(
            title: title,
            taskDescription: description.isEmpty ? nil : description,
            status: .todo,
            priority: priority,
            dueDate: hasDueDate ? dueDate : nil
        )
        Task {
            guard let writer else { return }
            _ = try? await writer.insert(task)
        }
        dismiss()
    }
}

// MARK: - Task Detail Sheet

struct TaskDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    var onSave: (TaskItem) -> Void
    var onDelete: () -> Void

    @State private var title: String
    @State private var description: String
    @State private var priority: TaskPriority
    @State private var status: TaskStatus
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var showDeleteConfirmation = false

    init(task: TaskItem, onSave: @escaping (TaskItem) -> Void, onDelete: @escaping () -> Void) {
        self.task = task
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: task.title)
        _description = State(initialValue: task.taskDescription ?? "")
        _priority = State(initialValue: task.priority)
        _status = State(initialValue: task.status)
        _hasDueDate = State(initialValue: task.dueDate != nil)
        _dueDate = State(initialValue: task.dueDate ?? Date())
    }

    var body: some View {
        NavigationStack {
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
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    private func saveTask() {
        // Create updated TaskItem directly
        let updated = TaskItem(
            id: task.id,
            title: title,
            taskDescription: description.isEmpty ? nil : description,
            status: status,
            priority: priority,
            dueDate: hasDueDate ? dueDate : nil,
            createdAt: task.createdAt,
            tags: task.decodedTags,
            projectId: task.projectId
        )
        onSave(updated)
        dismiss()
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (size, _) = computeLayout(proposal: proposal, subviews: subviews)
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (_, positions) = computeLayout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + positions[index].x, y: bounds.minY + positions[index].y), proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (CGSize, [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}
