import Foundation
import Archery

// MARK: - Task Repository (using @Repository macro)

/// Demonstrates the @Repository macro which generates:
/// - TaskRepositoryProtocol (protocol with all async methods)
/// - TaskRepositoryLive (production implementation with caching/tracing)
/// - MockTaskRepository (mock for testing)
@Repository
class TaskRepository {
    init() {}

    func getTasks() async throws -> [TaskItem] {
        // Simulate network delay
        try await Task.sleep(for: .milliseconds(500))
        return TaskItem.mockTasks
    }

    func getTask(id: String) async throws -> TaskItem {
        try await Task.sleep(for: .milliseconds(200))
        guard let task = TaskItem.mockTasks.first(where: { $0.id == id }) else {
            throw RepositoryError.notFound
        }
        return task
    }

    func createTask(_ task: TaskItem) async throws -> TaskItem {
        try await Task.sleep(for: .milliseconds(300))
        return task
    }

    func updateTask(_ task: TaskItem) async throws -> TaskItem {
        try await Task.sleep(for: .milliseconds(300))
        return task
    }

    func deleteTask(id: String) async throws {
        try await Task.sleep(for: .milliseconds(200))
    }
}

// MARK: - User Repository (using @Repository macro)

@Repository
class UserRepository {
    init() {}

    func getCurrentUser() async throws -> User {
        try await Task.sleep(for: .milliseconds(300))
        return User.mock
    }

    func updateUser(name: String?, avatar: String?) async throws -> User {
        try await Task.sleep(for: .milliseconds(400))
        return User.mock
    }

    func getUserPreferences() async throws -> [String: String] {
        try await Task.sleep(for: .milliseconds(200))
        return [:]
    }
}

// MARK: - Dashboard Repository (using @Repository macro)

@Repository
class DashboardRepository {
    init() {}

    func getStats() async throws -> DashboardStats {
        try await Task.sleep(for: .milliseconds(400))
        return DashboardStats.mock
    }

    func getActivityData(days: Int) async throws -> [ActivityDataPoint] {
        try await Task.sleep(for: .milliseconds(300))
        return ActivityDataPoint.mockWeek
    }

    func getInsights() async throws -> [Insight] {
        try await Task.sleep(for: .milliseconds(350))
        return []
    }
}

// MARK: - Supporting Types

struct Insight: Codable {
    let id: String
    let title: String
    let description: String
    let type: InsightType
    let value: String
    let trend: Trend
}

enum InsightType: String, Codable {
    case productivity
    case collaboration
    case deadline
    case achievement
}

enum Trend: String, Codable {
    case up
    case down
    case stable
}

struct AppNotification: Identifiable, Codable {
    let id: String
    let title: String
    let message: String
    let type: NotificationType
    let isRead: Bool
    let createdAt: Date
    let data: [String: String]?
}

enum NotificationType: String, Codable {
    case taskAssigned
    case taskCompleted
    case taskDue
    case projectUpdate
    case teamInvite
    case system
}
