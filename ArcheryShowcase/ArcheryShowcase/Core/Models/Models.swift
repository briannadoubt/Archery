import Foundation
import SwiftUI
import AppIntents
import Archery
import GRDB

// MARK: - User Models

struct User: Identifiable, Codable {
    let id: String
    let email: String
    let name: String
    let avatar: URL?
    let subscription: SubscriptionTier
    let createdAt: Date
    let settings: UserSettings?
    
    init(
        id: String = UUID().uuidString,
        email: String,
        name: String,
        avatar: URL? = nil,
        subscription: SubscriptionTier = .free,
        createdAt: Date = Date(),
        settings: UserSettings? = nil
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.avatar = avatar
        self.subscription = subscription
        self.createdAt = createdAt
        self.settings = settings
    }
}

struct UserSettings: Codable {
    var theme: AppTheme
    var notifications: NotificationSettings
    var privacy: PrivacySettings
}

enum SubscriptionTier: String, Codable {
    case free
    case premium
    case enterprise
}

// AppTheme is defined in DesignTokens.swift

// MARK: - Task Enums

// TaskItem is defined in AppDatabase.swift with full persistence support

@IntentEnum(displayName: "Status")
enum TaskStatus: String, AppEnum, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case todo
    case inProgress
    case completed
    case archived

    var title: String {
        switch self {
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .archived: return "Archived"
        }
    }

    var icon: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "clock"
        case .completed: return "checkmark.circle.fill"
        case .archived: return "archivebox"
        }
    }

    var color: Color {
        switch self {
        case .todo: return .secondary
        case .inProgress: return .blue
        case .completed: return .green
        case .archived: return .gray
        }
    }
}

@IntentEnum(displayName: "Priority")
enum TaskPriority: Int, AppEnum, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case low = 0
    case medium = 1
    case high = 2
    case urgent = 3

    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }

    var icon: String {
        switch self {
        case .low: return "arrow.down.circle"
        case .medium: return "minus.circle"
        case .high: return "arrow.up.circle"
        case .urgent: return "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

struct Subtask: Identifiable, Codable {
    let id: String
    let title: String
    let isCompleted: Bool
}

struct Attachment: Identifiable, Codable {
    let id: String
    let name: String
    let url: URL
    let type: AttachmentType
    let size: Int64
}

enum AttachmentType: String, Codable {
    case image
    case document
    case video
    case audio
    case other
}

// MARK: - Project Models

struct Project: Identifiable, Codable {
    let id: String
    let name: String
    let description: String?
    let color: String
    let icon: String
    let createdAt: Date
    let members: [User]
    let taskCount: Int
    let completedTaskCount: Int
    
    var progress: Double {
        guard taskCount > 0 else { return 0 }
        return Double(completedTaskCount) / Double(taskCount)
    }
}

// MARK: - Dashboard Models

struct DashboardStats: Codable {
    let totalTasks: Int
    let completedTasks: Int
    let inProgressTasks: Int
    let overdueTaskss: Int
    let thisWeekTasks: Int
    let teamMembers: Int
    let activeProjects: Int
}

struct ActivityDataPoint: Identifiable, Codable {
    var id = UUID()
    let day: String
    let date: Date
    let count: Int
}

// MARK: - Notification Models

struct NotificationSettings: Codable {
    var pushEnabled: Bool
    var emailEnabled: Bool
    var taskReminders: Bool
    var dailySummary: Bool
    var weeklyReport: Bool
}

struct PrivacySettings: Codable {
    var profileVisibility: ProfileVisibility
    var shareAnalytics: Bool
    var showOnlineStatus: Bool
}

enum ProfileVisibility: String, Codable {
    case `public`
    case team
    case `private`
}

// MARK: - Auth Models

struct AuthCredentials: Codable {
    let user: User
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

enum AuthError: LocalizedError {
    case notAuthenticated
    case invalidCredentials
    case networkError
    case serverError(Int)
    case socialLoginFailed(String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Authentication required"
        case .invalidCredentials:
            return "Invalid email or password"
        case .networkError:
            return "Network connection error"
        case .serverError(let code):
            return "Server error: \(code)"
        case .socialLoginFailed(let provider):
            return "\(provider) login failed"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
    
    var analyticsReason: String {
        switch self {
        case .notAuthenticated:
            return "not_authenticated"
        case .invalidCredentials:
            return "invalid_credentials"
        case .networkError:
            return "network_error"
        case .serverError(let code):
            return "server_error_\(code)"
        case .socialLoginFailed(let provider):
            return "social_login_failed_\(provider.lowercased())"
        case .unknown:
            return "unknown_error"
        }
    }
}

// MARK: - Form Models

struct FormField: Identifiable {
    let id = UUID()
    let label: String
    let type: FieldType
    let validation: [ValidationRule]
    let isRequired: Bool
    
    enum FieldType {
        case text
        case email
        case password
        case number
        case date
        case picker([String])
        case toggle
        case multiline
    }
}

struct ValidationRule {
    let validate: (Any) -> Bool
    let errorMessage: String
}

// MARK: - Analytics Events

enum AnalyticsEvent {
    case appLaunched
    case userLoggedIn(method: String)
    case userLoggedOut
    case loginFailed(reason: String)
    case dashboardViewed
    case taskListViewed(count: Int)
    case taskCreated(id: String)
    case taskDeleted(id: String)
    case taskCompleted(id: String)
    case taskArchived(id: String)
    case formSubmitted(type: String)
    case error(code: String, message: String)
}

// MARK: - Mock Data

extension User {
    static let mock = User(
        id: "user-1",
        email: "demo@archery.app",
        name: "Demo User"
    )
}

extension TaskItem {
    static let mockTasks: [TaskItem] = [
        TaskItem(id: "1", title: "Review pull request", taskDescription: "Check the latest changes", status: .inProgress, priority: .high, dueDate: Date().addingTimeInterval(3600), tags: ["work", "urgent"]),
        TaskItem(id: "2", title: "Update documentation", taskDescription: "Add examples for new APIs", status: .todo, priority: .medium, dueDate: Date().addingTimeInterval(86400), tags: ["docs"]),
        TaskItem(id: "3", title: "Fix login bug", taskDescription: "Handle edge case for social login", status: .todo, priority: .urgent, dueDate: Date(), tags: ["bug", "auth"]),
        TaskItem(id: "4", title: "Design system update", taskDescription: "Refresh color tokens", status: .inProgress, priority: .medium, tags: ["design"]),
        TaskItem(id: "5", title: "Weekly team sync", status: .completed, priority: .low, dueDate: Date().addingTimeInterval(-86400)),
        TaskItem(id: "6", title: "Performance optimization", taskDescription: "Improve app launch time", status: .todo, priority: .high, dueDate: Date().addingTimeInterval(172800), tags: ["performance"]),
    ]
}

extension DashboardStats {
    static let mock = DashboardStats(
        totalTasks: 42,
        completedTasks: 28,
        inProgressTasks: 8,
        overdueTaskss: 2,
        thisWeekTasks: 12,
        teamMembers: 5,
        activeProjects: 3
    )
}

extension ActivityDataPoint {
    static let mockWeek: [ActivityDataPoint] = [
        ActivityDataPoint(day: "Mon", date: Date().addingTimeInterval(-6*86400), count: 8),
        ActivityDataPoint(day: "Tue", date: Date().addingTimeInterval(-5*86400), count: 12),
        ActivityDataPoint(day: "Wed", date: Date().addingTimeInterval(-4*86400), count: 6),
        ActivityDataPoint(day: "Thu", date: Date().addingTimeInterval(-3*86400), count: 15),
        ActivityDataPoint(day: "Fri", date: Date().addingTimeInterval(-2*86400), count: 9),
        ActivityDataPoint(day: "Sat", date: Date().addingTimeInterval(-86400), count: 3),
        ActivityDataPoint(day: "Sun", date: Date(), count: 5),
    ]
}
