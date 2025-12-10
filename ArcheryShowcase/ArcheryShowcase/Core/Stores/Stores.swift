import Foundation
import Archery

// MARK: - User Preferences Store (using @KeyValueStore macro)

/// Demonstrates the @KeyValueStore macro which generates a Store struct
/// with typed getters/setters for each case.
@KeyValueStore
enum UserPreferencesKey {
    case theme(String)
    case compactMode(Bool)
    case showCompletedTasks(Bool)
    case defaultTaskPriority(String)
    case notificationsEnabled(Bool)
    case soundEnabled(Bool)
    case hapticEnabled(Bool)
    case autoSync(Bool)
    case syncInterval(TimeInterval)
    case language(String)
}

// MARK: - Onboarding Store (using @KeyValueStore macro)

@KeyValueStore
enum OnboardingKey {
    case hasCompletedOnboarding(Bool)
    case hasSeenDashboardTip(Bool)
    case hasSeenTaskListTip(Bool)
    case hasSeenSwipeGestureTip(Bool)
    case hasSeenSettingsTip(Bool)
    case onboardingVersion(String)
}

// MARK: - Feature Flags Store (using @KeyValueStore macro)

@KeyValueStore
enum FeatureFlagsKey {
    case debugMode(Bool)
    case experimentalFeatures(Bool)
    case betaFeatures(Bool)
    case performanceMonitoring(Bool)
    case crashReporting(Bool)
    case analyticsEnabled(Bool)
}

// MARK: - Sync Store (using @KeyValueStore macro)

@KeyValueStore
enum SyncKey {
    case lastSyncDate(Date)
    case pendingChanges(Int)
    case conflictResolutionStrategy(String)
}

// MARK: - Supporting Types

enum ConflictResolutionStrategy: String, Codable {
    case serverWins
    case clientWins
    case merge
    case manual
}

struct SyncError: Codable {
    let id: String
    let error: String
    let timestamp: Date
    let retryCount: Int
}

// MARK: - Draft Store (using @KeyValueStore macro)

@KeyValueStore
enum DraftKey {
    case taskDraft(TaskDraft)
    case projectDraft(ProjectDraft)
    case noteDraft(String)
}

struct TaskDraft: Codable {
    let title: String
    let description: String
    let priority: TaskPriority
    let dueDate: Date?
    let tags: [String]
    let savedAt: Date
}

struct ProjectDraft: Codable {
    let name: String
    let description: String
    let color: String
    let icon: String
    let members: [String]
    let savedAt: Date
}

// MARK: - Cache Store (ObservableObject for UI state)

class CacheStore: ObservableObject {
    @Published var dashboardStats: DashboardStats?
    @Published var recentTasks: [TaskItem] = []
    @Published var userProfile: User?
    @Published var projects: [Project] = []
    @Published var activityData: [ActivityDataPoint] = []
}
