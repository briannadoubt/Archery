import Foundation
import SwiftUI
import Archery
import AppIntents

// MARK: - Task Model

/// Primary task model for the app - stored in database with full enum support.
///
/// Uses GRDB's `DatabaseValueConvertible` to store enums directly:
/// - `status: TaskStatus` stored as TEXT in SQLite
/// - `priority: TaskPriority` stored as INTEGER in SQLite
///
/// The `@Persistable` macro generates:
/// - Members: Columns enum, databaseTableName, createTableMigration
/// - Members (when AppEntity declared): defaultQuery, typeDisplayRepresentation, displayRepresentation,
///   EntityQuery, CreateIntent, ListIntent, DeleteIntent, Shortcuts
/// - Conformances via extension: AutoMigrating (and Identifiable, Hashable, Sendable in database-only mode)
///
/// For App Intents mode: declare `Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord, AppEntity`
/// This avoids Swift 6 actor isolation conflicts between AppEntity (MainActor) and FetchableRecord (Sendable).
///
/// Usage with `@Query`:
/// ```swift
/// @Query(TaskItem.all()) var tasks: [TaskItem]
/// ```
@Persistable(
    table: "tasks",
    displayName: "Task",
    titleProperty: "title"
)
struct TaskItem: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord, AppEntity {
    @PrimaryKey var id: String
    var title: String
    var taskDescription: String?
    @Indexed var status: TaskStatus
    @ColumnType(.integer) var priority: TaskPriority
    @Indexed var dueDate: Date?
    @CreatedAt var createdAt: Date
    @Default("[]") var tags: String    // JSON-encoded array
    @ForeignKey(PersistentProject.self) @Indexed var projectId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case taskDescription = "description"
        case status
        case priority
        case dueDate = "due_date"
        case createdAt = "created_at"
        case tags
        case projectId = "project_id"
    }

    // MARK: - Initializers

    init(
        id: String = UUID().uuidString,
        title: String,
        taskDescription: String? = nil,
        status: TaskStatus = .todo,
        priority: TaskPriority = .medium,
        dueDate: Date? = nil,
        createdAt: Date = Date(),
        tags: [String] = [],
        projectId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.taskDescription = taskDescription
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.tags = (try? JSONEncoder().encode(tags)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.projectId = projectId
    }

    // MARK: - Computed Properties

    /// Whether the task is marked as completed
    var isCompleted: Bool { status == .completed }

    /// Decoded tags array from JSON storage
    var decodedTags: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(tags.utf8))) ?? []
    }

    /// Section title for grouping in lists (by due date or completion)
    var sectionTitle: String {
        if isCompleted {
            return "Completed"
        } else if let dueDate = dueDate {
            let calendar = Calendar.current
            if calendar.isDateInToday(dueDate) {
                return "Today"
            } else if calendar.isDateInTomorrow(dueDate) {
                return "Tomorrow"
            } else if dueDate < Date() {
                return "Overdue"
            } else {
                return "Upcoming"
            }
        } else {
            return "No Due Date"
        }
    }

    // MARK: - Tag Helpers

    /// Set tags from an array (encodes to JSON)
    mutating func setTags(_ newTags: [String]) {
        tags = (try? JSONEncoder().encode(newTags)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    /// Add a tag
    mutating func addTag(_ tag: String) {
        var current = decodedTags
        if !current.contains(tag) {
            current.append(tag)
            setTags(current)
        }
    }

    /// Remove a tag
    mutating func removeTag(_ tag: String) {
        var current = decodedTags
        current.removeAll { $0 == tag }
        setTags(current)
    }
}

// MARK: - Project Model

@Persistable(
    table: "projects",
    displayName: "Project",
    titleProperty: "name"
)
struct PersistentProject: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord, AppEntity {
    @PrimaryKey var id: String
    var name: String
    var projectDescription: String?
    var color: String
    var icon: String
    @CreatedAt var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case projectDescription = "description"
        case color
        case icon
        case createdAt = "created_at"
    }

    init(id: String = UUID().uuidString, name: String, projectDescription: String? = nil, color: String, icon: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.projectDescription = projectDescription
        self.color = color
        self.icon = icon
        self.createdAt = createdAt
    }

    func toProject(taskCount: Int = 0, completedTaskCount: Int = 0) -> Project {
        Project(
            id: id,
            name: name,
            description: projectDescription,
            color: color,
            icon: icon,
            createdAt: createdAt,
            members: [],
            taskCount: taskCount,
            completedTaskCount: completedTaskCount
        )
    }
}

// MARK: - Query Builders for SwiftUI

extension TaskItem {
    /// All tasks ordered by due date
    static func allByDueDate() -> QueryBuilder<TaskItem> {
        TaskItem.all().order(by: Columns.dueDate, ascending: true)
    }

    /// Tasks filtered by status
    static func withStatus(_ status: TaskStatus) -> QueryBuilder<TaskItem> {
        TaskItem.all().filter(Columns.status == status)
    }

    /// Tasks for a specific project
    static func forProject(_ projectId: String) -> QueryBuilder<TaskItem> {
        TaskItem.all().filter(Columns.projectId == projectId)
    }

    /// Incomplete tasks (not completed or archived)
    static func incomplete() -> QueryBuilder<TaskItem> {
        TaskItem.all()
            .filter(Columns.status != TaskStatus.completed)
            .filter(Columns.status != TaskStatus.archived)
    }

    /// Overdue tasks
    static func overdue() -> QueryBuilder<TaskItem> {
        TaskItem.all()
            .filter(Columns.status != TaskStatus.completed)
            .filter(Columns.dueDate < Date())
    }

    /// High priority tasks
    static func highPriority() -> QueryBuilder<TaskItem> {
        TaskItem.all()
            .filter(Columns.priority >= TaskPriority.high)
            .order(by: Columns.priority, ascending: false)
    }

    /// Tasks due today
    static func dueToday() -> QueryBuilder<TaskItem> {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return TaskItem.all()
            .filter(Columns.dueDate >= startOfDay)
            .filter(Columns.dueDate < endOfDay)
    }
}

extension PersistentProject {
    /// All projects ordered by name
    static func allByName() -> QueryBuilder<PersistentProject> {
        PersistentProject.all().order(by: Columns.name, ascending: true)
    }
}

// MARK: - Query Sources

extension TaskItem: HasQuerySources {
    @QuerySources
    struct Sources: Sendable {
        /// All tasks (unordered)
        var all: QuerySource<TaskItem> {
            QuerySource(TaskItem.all())
        }

        /// All tasks ordered by creation date (newest first)
        var byCreatedAt: QuerySource<TaskItem> {
            QuerySource(TaskItem.all().order(by: Columns.createdAt, ascending: false))
        }

        /// Recent tasks (last 20, newest first)
        var recent: QuerySource<TaskItem> {
            QuerySource(TaskItem.all().order(by: Columns.createdAt, ascending: false).limit(20))
        }
    }
}

extension PersistentProject: HasQuerySources {
    @QuerySources
    struct Sources: Sendable {
        /// All projects
        var all: QuerySource<PersistentProject> {
            QuerySource(PersistentProject.all())
        }
    }
}

