import Foundation
import SwiftUI
import Archery
import GRDB

// MARK: - Persistent Task Model

/// TaskItem adapted for GRDB persistence
/// Uses the same structure as the app's TaskItem but with GRDB conformances
@Persistable(table: "tasks")
struct PersistentTask: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    var id: String
    var title: String
    var taskDescription: String?
    var status: String  // Stored as string, converted to TaskStatus
    var priority: Int   // Stored as int, converted to TaskPriority
    var dueDate: Date?
    var createdAt: Date
    var tags: String    // JSON-encoded array
    var projectId: String?

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

    // Convert from app's TaskItem
    init(from taskItem: TaskItem) {
        self.id = taskItem.id
        self.title = taskItem.title
        self.taskDescription = taskItem.description
        self.status = taskItem.status.rawValue
        self.priority = taskItem.priority.rawValue
        self.dueDate = taskItem.dueDate
        self.createdAt = taskItem.createdAt
        self.tags = (try? JSONEncoder().encode(taskItem.tags)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.projectId = taskItem.projectId
    }

    // Convert to app's TaskItem
    func toTaskItem() -> TaskItem {
        let decodedTags: [String] = (try? JSONDecoder().decode([String].self, from: Data(tags.utf8))) ?? []
        return TaskItem(
            id: id,
            title: title,
            description: taskDescription,
            status: TaskStatus(rawValue: status) ?? .todo,
            priority: TaskPriority(rawValue: priority) ?? .medium,
            dueDate: dueDate,
            tags: decodedTags,
            projectId: projectId,
            createdAt: createdAt
        )
    }
}

// MARK: - Persistent Project Model

@Persistable(table: "projects")
struct PersistentProject: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    var id: String
    var name: String
    var projectDescription: String?
    var color: String
    var icon: String
    var createdAt: Date

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

// MARK: - App Database Container

/// Main database container for the ArcheryShowcase app
@MainActor
final class AppDatabase: ObservableObject {
    static let shared = AppDatabase()

    private(set) var container: GRDBContainer?
    @Published var isReady = false
    @Published var error: Error?

    private init() {}

    /// Initialize the database
    func setup() async {
        guard container == nil else { return }

        do {
            // Use file-based database for persistence
            let dbURL = AppDatabase.databaseURL
            container = try GRDBContainer.file(at: dbURL)

            // Run migrations
            try appMigrations.run(on: container!)

            // Seed demo data if empty
            try await seedDemoDataIfNeeded()

            isReady = true
        } catch {
            self.error = error
            print("Database setup failed: \(error)")
        }
    }

    /// Create an in-memory database for previews
    static func preview() -> AppDatabase {
        let db = AppDatabase()
        Task { @MainActor in
            do {
                db.container = try GRDBContainer.inMemory()
                try appMigrations.run(on: db.container!)
                try await db.seedDemoData()
                db.isReady = true
            } catch {
                db.error = error
            }
        }
        return db
    }

    private static var databaseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ArcheryShowcase")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("app.sqlite")
    }

    // MARK: - Writers

    var writer: GRDBWriter? {
        guard let container else { return nil }
        return GRDBWriter(container: container)
    }
}

// MARK: - Migrations

private let appMigrations = GRDBMigrationRunner {
    GRDBMigration(id: "v1_create_tasks") { db in
        try db.create(table: "tasks") { t in
            t.primaryKey("id", .text)
            t.column("title", .text).notNull()
            t.column("description", .text)
            t.column("status", .text).notNull().defaults(to: "todo")
            t.column("priority", .integer).notNull().defaults(to: 1)
            t.column("due_date", .datetime)
            t.column("created_at", .datetime).notNull()
            t.column("tags", .text).notNull().defaults(to: "[]")
            t.column("project_id", .text)
        }

        // Index for common queries
        try db.create(index: "tasks_status_idx", on: "tasks", columns: ["status"])
        try db.create(index: "tasks_due_date_idx", on: "tasks", columns: ["due_date"])
        try db.create(index: "tasks_project_id_idx", on: "tasks", columns: ["project_id"])
    }

    GRDBMigration(id: "v1_create_projects") { db in
        try db.create(table: "projects") { t in
            t.primaryKey("id", .text)
            t.column("name", .text).notNull()
            t.column("description", .text)
            t.column("color", .text).notNull()
            t.column("icon", .text).notNull()
            t.column("created_at", .datetime).notNull()
        }
    }
}

// MARK: - Demo Data Seeding

extension AppDatabase {
    private func seedDemoDataIfNeeded() async throws {
        guard let container else { return }

        let taskCount = try await container.read { db in
            try PersistentTask.fetchCount(db)
        }

        if taskCount == 0 {
            try await seedDemoData()
        }
    }

    func seedDemoData() async throws {
        guard let container else { return }

        try await container.write { db in
            // Seed projects
            let projects = [
                PersistentProject(id: "proj-1", name: "Mobile App", projectDescription: "iOS and Android development", color: "blue", icon: "iphone"),
                PersistentProject(id: "proj-2", name: "Backend API", projectDescription: "Server infrastructure", color: "green", icon: "server.rack"),
                PersistentProject(id: "proj-3", name: "Design System", projectDescription: "UI/UX components", color: "purple", icon: "paintbrush"),
            ]

            for project in projects {
                try project.insert(db)
            }

            // Seed tasks
            let tasks = [
                PersistentTask(from: TaskItem(id: "task-1", title: "Review pull request", description: "Check the latest changes for the auth module", status: .inProgress, priority: .high, dueDate: Date().addingTimeInterval(3600), tags: ["code-review", "urgent"], projectId: "proj-1")),
                PersistentTask(from: TaskItem(id: "task-2", title: "Update API documentation", description: "Add examples for new endpoints", status: .todo, priority: .medium, dueDate: Date().addingTimeInterval(86400), tags: ["docs"], projectId: "proj-2")),
                PersistentTask(from: TaskItem(id: "task-3", title: "Fix login bug", description: "Handle edge case for social login timeout", status: .todo, priority: .urgent, dueDate: Date(), tags: ["bug", "auth"], projectId: "proj-1")),
                PersistentTask(from: TaskItem(id: "task-4", title: "Design system audit", description: "Review color tokens for accessibility", status: .inProgress, priority: .medium, tags: ["design", "a11y"], projectId: "proj-3")),
                PersistentTask(from: TaskItem(id: "task-5", title: "Weekly team sync", description: "Sprint planning meeting", status: .completed, priority: .low, dueDate: Date().addingTimeInterval(-86400), tags: ["meeting"])),
                PersistentTask(from: TaskItem(id: "task-6", title: "Performance optimization", description: "Improve app launch time by 30%", status: .todo, priority: .high, dueDate: Date().addingTimeInterval(172800), tags: ["performance"], projectId: "proj-1")),
                PersistentTask(from: TaskItem(id: "task-7", title: "Write unit tests", description: "Increase code coverage to 80%", status: .todo, priority: .medium, dueDate: Date().addingTimeInterval(259200), tags: ["testing"], projectId: "proj-2")),
                PersistentTask(from: TaskItem(id: "task-8", title: "Setup CI/CD pipeline", description: "Automate deployment process", status: .completed, priority: .high, tags: ["devops"], projectId: "proj-2")),
            ]

            for task in tasks {
                try task.insert(db)
            }
        }
    }

    /// Clear all data (for testing/reset)
    func clearAllData() async throws {
        guard let container else { return }

        try await container.write { db in
            try PersistentTask.deleteAll(db)
            try PersistentProject.deleteAll(db)
        }
    }
}

// MARK: - Query Builders for SwiftUI

extension PersistentTask {
    /// All tasks ordered by due date
    static func allByDueDate() -> GRDBQueryBuilder<PersistentTask> {
        PersistentTask.all().order(by: Columns.dueDate, ascending: true)
    }

    /// Tasks filtered by status
    static func withStatus(_ status: TaskStatus) -> GRDBQueryBuilder<PersistentTask> {
        PersistentTask.all().filter(Columns.status == status.rawValue)
    }

    /// Tasks for a specific project
    static func forProject(_ projectId: String) -> GRDBQueryBuilder<PersistentTask> {
        PersistentTask.all().filter(Columns.projectId == projectId)
    }

    /// Incomplete tasks (not completed or archived)
    static func incomplete() -> GRDBQueryBuilder<PersistentTask> {
        PersistentTask.all()
            .filter(Columns.status != TaskStatus.completed.rawValue)
            .filter(Columns.status != TaskStatus.archived.rawValue)
    }

    /// Overdue tasks
    static func overdue() -> GRDBQueryBuilder<PersistentTask> {
        PersistentTask.all()
            .filter(Columns.status != TaskStatus.completed.rawValue)
            .filter(Columns.dueDate < Date())
    }
}

extension PersistentProject {
    /// All projects ordered by name
    static func allByName() -> GRDBQueryBuilder<PersistentProject> {
        PersistentProject.all().order(by: Columns.name, ascending: true)
    }
}

// MARK: - Environment Key

private struct AppDatabaseKey: EnvironmentKey {
    static let defaultValue: AppDatabase? = nil
}

extension EnvironmentValues {
    var appDatabase: AppDatabase? {
        get { self[AppDatabaseKey.self] }
        set { self[AppDatabaseKey.self] = newValue }
    }
}

extension View {
    func appDatabase(_ database: AppDatabase) -> some View {
        environment(\.appDatabase, database)
            .grdbContainer(database.container ?? (try! GRDBContainer.inMemory()))
    }
}
