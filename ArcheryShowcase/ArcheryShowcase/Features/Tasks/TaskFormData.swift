import Foundation
import Archery

// MARK: - Task Form Data

/// Form data for creating or editing tasks.
/// Uses simple validation without the @Form macro.
struct TaskFormData {
    var title: String
    var taskDescription: String
    var priority: Int
    var dueDate: Date?
    var tags: String

    // MARK: - Initialization

    init(
        title: String = "",
        taskDescription: String = "",
        priority: Int = 1,
        dueDate: Date? = nil,
        tags: String = ""
    ) {
        self.title = title
        self.taskDescription = taskDescription
        self.priority = priority
        self.dueDate = dueDate
        self.tags = tags
    }

    // MARK: - Validation

    /// Validates the form data
    func validate() -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        title.count <= 200 &&
        taskDescription.count <= 1000
    }

    /// Check if form has required data for save
    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Conversion

    /// Convert to TaskItem for database storage
    func toTaskItem() -> TaskItem {
        let tagList = tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return TaskItem(
            title: title,
            taskDescription: taskDescription.isEmpty ? nil : taskDescription,
            status: .todo,
            priority: TaskPriority(rawValue: priority) ?? .medium,
            dueDate: dueDate,
            tags: tagList
        )
    }

    /// Create from existing TaskItem for editing
    static func from(_ task: TaskItem) -> TaskFormData {
        TaskFormData(
            title: task.title,
            taskDescription: task.taskDescription ?? "",
            priority: task.priority.rawValue,
            dueDate: task.dueDate,
            tags: task.decodedTags.joined(separator: ", ")
        )
    }

    /// Priority as enum
    var taskPriority: TaskPriority {
        get { TaskPriority(rawValue: priority) ?? .medium }
        set { priority = newValue.rawValue }
    }
}
