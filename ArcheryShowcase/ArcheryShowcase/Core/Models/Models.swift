import Foundation
import SwiftUI

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

enum AppTheme: String, Codable, CaseIterable {
    case system
    case light
    case dark
    
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

// MARK: - Task Models

struct Task: Identifiable, Codable {
    let id: String
    let title: String
    let description: String?
    let isCompleted: Bool
    let priority: TaskPriority
    let dueDate: Date?
    let createdAt: Date
    let updatedAt: Date
    let project: Project?
    let assignee: User?
    let tags: [String]
    let attachments: [Attachment]
    let subtasks: [Subtask]
    
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
}

enum TaskPriority: Int, Codable, CaseIterable {
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
    let id = UUID()
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
    case public
    case team
    case private
}

// MARK: - Auth Models

struct AuthCredentials: Codable {
    let user: User
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

enum AuthError: LocalizedError {
    case invalidCredentials
    case networkError
    case serverError(Int)
    case socialLoginFailed(String)
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
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