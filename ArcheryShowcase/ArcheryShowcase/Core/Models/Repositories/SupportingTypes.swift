import Foundation
import Archery

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
