import Foundation
import Archery

// MARK: - User Preferences Store

@KeyValueStore(
    namespace: "userPreferences",
    defaults: [
        "theme": AppTheme.system,
        "compactMode": false,
        "showCompletedTasks": true,
        "defaultTaskPriority": TaskPriority.medium,
        "notificationsEnabled": true,
        "soundEnabled": true,
        "hapticEnabled": true,
        "autoSync": true,
        "syncInterval": 300, // 5 minutes
        "language": "en",
        "firstLaunchDate": Date()
    ]
)
enum UserPreferencesStore {
    case theme(AppTheme)
    case compactMode(Bool)
    case showCompletedTasks(Bool)
    case defaultTaskPriority(TaskPriority)
    case notificationsEnabled(Bool)
    case soundEnabled(Bool)
    case hapticEnabled(Bool)
    case autoSync(Bool)
    case syncInterval(TimeInterval)
    case language(String)
    case firstLaunchDate(Date)
}

// MARK: - Cache Store

@KeyValueStore(
    namespace: "cache",
    defaults: [:],
    expiration: 3600 // 1 hour default expiration
)
enum CacheStore {
    case dashboardStats(DashboardStats)
    case recentTasks([Task])
    case userProfile(User)
    case projects([Project])
    case activityData([ActivityDataPoint])
    case searchResults(String, [Task]) // Query and results
    case imageCache(URL, Data)
}

// MARK: - Keychain Store

@KeyValueStore(
    namespace: "keychain",
    secure: true,
    defaults: [:]
)
enum KeychainStore {
    case accessToken(String)
    case refreshToken(String)
    case apiKey(String)
    case userCredentials(AuthCredentials)
    case biometricEnabled(Bool)
    case pinCode(String)
}

// MARK: - Onboarding Store

@KeyValueStore(
    namespace: "onboarding",
    defaults: [
        "hasCompletedOnboarding": false,
        "hasSeenDashboardTip": false,
        "hasSeenTaskListTip": false,
        "hasSeenSwipeGestureTip": false,
        "hasSeenSettingsTip": false,
        "onboardingVersion": "1.0.0"
    ]
)
enum OnboardingStore {
    case hasCompletedOnboarding(Bool)
    case hasSeenDashboardTip(Bool)
    case hasSeenTaskListTip(Bool)
    case hasSeenSwipeGestureTip(Bool)
    case hasSeenSettingsTip(Bool)
    case onboardingVersion(String)
}

// MARK: - Feature Store

@KeyValueStore(
    namespace: "features",
    defaults: [
        "debugMode": false,
        "experimentalFeatures": false,
        "betaFeatures": false,
        "performanceMonitoring": true,
        "crashReporting": true,
        "analyticsEnabled": true
    ]
)
enum FeatureStore {
    case debugMode(Bool)
    case experimentalFeatures(Bool)
    case betaFeatures(Bool)
    case performanceMonitoring(Bool)
    case crashReporting(Bool)
    case analyticsEnabled(Bool)
}

// MARK: - Sync Store

@KeyValueStore(
    namespace: "sync",
    defaults: [
        "lastSyncDate": Date.distantPast,
        "syncInProgress": false,
        "pendingChanges": 0,
        "conflictResolutionStrategy": ConflictResolutionStrategy.serverWins
    ]
)
enum SyncStore {
    case lastSyncDate(Date)
    case syncInProgress(Bool)
    case pendingChanges(Int)
    case conflictResolutionStrategy(ConflictResolutionStrategy)
    case syncErrors([SyncError])
}

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

// MARK: - Draft Store

@KeyValueStore(
    namespace: "drafts",
    defaults: [:],
    autoSave: true
)
enum DraftStore {
    case taskDraft(TaskDraft)
    case projectDraft(ProjectDraft)
    case noteDraft(String)
    case formData([String: Any])
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