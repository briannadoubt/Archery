import Foundation
import Archery

// MARK: - Task Repository

@Repository(
    endpoints: [
        .init(name: "getTasks", method: .get, path: "/tasks"),
        .init(name: "getTask", method: .get, path: "/tasks/{id}"),
        .init(name: "createTask", method: .post, path: "/tasks"),
        .init(name: "updateTask", method: .put, path: "/tasks/{id}"),
        .init(name: "deleteTask", method: .delete, path: "/tasks/{id}"),
        .init(name: "archiveTask", method: .post, path: "/tasks/{id}/archive"),
        .init(name: "getRecentTasks", method: .get, path: "/tasks/recent")
    ],
    mockData: true,
    caching: true,
    retryPolicy: .exponentialBackoff(maxRetries: 3)
)
protocol TaskRepository {
    func getTasks(page: Int, limit: Int, filter: TaskFilter, sort: TaskSort) async throws -> [Task]
    func getTask(id: String) async throws -> Task
    func createTask(_ task: Task) async throws -> Task
    func updateTask(_ id: String, updates: [String: Any]) async throws -> Task
    func deleteTask(_ id: String) async throws
    func archiveTask(_ id: String) async throws
    func getRecentTasks(limit: Int) async throws -> [Task]
}

// MARK: - User Repository

@Repository(
    endpoints: [
        .init(name: "getCurrentUser", method: .get, path: "/user/me"),
        .init(name: "updateUser", method: .put, path: "/user/me"),
        .init(name: "getUser", method: .get, path: "/users/{id}"),
        .init(name: "searchUsers", method: .get, path: "/users/search"),
        .init(name: "updateSettings", method: .put, path: "/user/settings")
    ],
    mockData: true
)
protocol UserRepository {
    func getCurrentUser() async throws -> User
    func updateUser(_ updates: [String: Any]) async throws -> User
    func getUser(id: String) async throws -> User
    func searchUsers(query: String) async throws -> [User]
    func updateSettings(_ settings: UserSettings) async throws
}

// MARK: - Project Repository

@Repository(
    endpoints: [
        .init(name: "getProjects", method: .get, path: "/projects"),
        .init(name: "getProject", method: .get, path: "/projects/{id}"),
        .init(name: "createProject", method: .post, path: "/projects"),
        .init(name: "updateProject", method: .put, path: "/projects/{id}"),
        .init(name: "deleteProject", method: .delete, path: "/projects/{id}"),
        .init(name: "addMember", method: .post, path: "/projects/{id}/members"),
        .init(name: "removeMember", method: .delete, path: "/projects/{id}/members/{userId}")
    ],
    mockData: true,
    caching: true
)
protocol ProjectRepository {
    func getProjects() async throws -> [Project]
    func getProject(id: String) async throws -> Project
    func createProject(_ project: Project) async throws -> Project
    func updateProject(_ id: String, updates: [String: Any]) async throws -> Project
    func deleteProject(_ id: String) async throws
    func addMember(projectId: String, userId: String) async throws
    func removeMember(projectId: String, userId: String) async throws
}

// MARK: - Dashboard Repository

@Repository(
    endpoints: [
        .init(name: "getStats", method: .get, path: "/dashboard/stats"),
        .init(name: "getActivityData", method: .get, path: "/dashboard/activity"),
        .init(name: "getInsights", method: .get, path: "/dashboard/insights")
    ],
    mockData: true,
    caching: true,
    cacheDuration: 300 // 5 minutes
)
protocol DashboardRepository {
    func getStats() async throws -> DashboardStats
    func getActivityData(days: Int) async throws -> [ActivityDataPoint]
    func getInsights() async throws -> [Insight]
}

// MARK: - Auth Repository

@Repository(
    endpoints: [
        .init(name: "login", method: .post, path: "/auth/login"),
        .init(name: "logout", method: .post, path: "/auth/logout"),
        .init(name: "refreshToken", method: .post, path: "/auth/refresh"),
        .init(name: "loginWithApple", method: .post, path: "/auth/apple"),
        .init(name: "loginWithGoogle", method: .post, path: "/auth/google"),
        .init(name: "register", method: .post, path: "/auth/register"),
        .init(name: "forgotPassword", method: .post, path: "/auth/forgot-password"),
        .init(name: "resetPassword", method: .post, path: "/auth/reset-password")
    ],
    mockData: true,
    retryPolicy: .none // Don't retry auth requests
)
protocol AuthRepository {
    func login(email: String, password: String) async throws -> AuthCredentials
    func logout() async throws
    func refreshToken(_ token: String) async throws -> AuthCredentials
    func loginWithApple() async throws -> AuthCredentials
    func loginWithGoogle() async throws -> AuthCredentials
    func register(email: String, password: String, name: String) async throws -> AuthCredentials
    func forgotPassword(email: String) async throws
    func resetPassword(token: String, newPassword: String) async throws
}

// MARK: - Notification Repository

@Repository(
    endpoints: [
        .init(name: "getNotifications", method: .get, path: "/notifications"),
        .init(name: "markAsRead", method: .post, path: "/notifications/{id}/read"),
        .init(name: "markAllAsRead", method: .post, path: "/notifications/read-all"),
        .init(name: "deleteNotification", method: .delete, path: "/notifications/{id}"),
        .init(name: "getUnreadCount", method: .get, path: "/notifications/unread-count")
    ],
    mockData: true,
    caching: true
)
protocol NotificationRepository {
    func getNotifications(page: Int, limit: Int) async throws -> [Notification]
    func markAsRead(id: String) async throws
    func markAllAsRead() async throws
    func deleteNotification(id: String) async throws
    func getUnreadCount() async throws -> Int
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

struct Notification: Identifiable, Codable {
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