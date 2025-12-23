import Foundation
import Archery

// MARK: - App Settings

/// User preferences stored with @KeyValueStore macro.
/// The macro generates a `Store` struct with typed accessors.
///
/// Usage:
/// ```swift
/// var store = AppSettings.Store(initialValues: savedData)
/// let theme = try await store.theme(default: "system")
/// try await store.setTheme("dark")
/// ```
@KeyValueStore
enum AppSettings {
    /// User's preferred theme (system/light/dark)
    case theme(String)

    /// Default priority for new tasks
    case defaultTaskPriority(Int)

    /// Whether to show completed tasks in list
    case showCompletedTasks(Bool)

    /// Number of days to show in upcoming view
    case upcomingDaysRange(Int)

    /// Whether daily reminder notifications are enabled
    case dailyReminderEnabled(Bool)

    /// Time for daily reminder (minutes from midnight)
    case dailyReminderTime(Int)

    /// Last sync timestamp
    case lastSyncDate(Date)
}

// MARK: - Settings Manager

/// Observable manager for app settings.
/// Uses UserDefaults for persistence.
@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard
    private let keyPrefix = "AppSettings."

    // Published properties for SwiftUI binding
    @Published var theme: String {
        didSet { defaults.set(theme, forKey: keyPrefix + "theme") }
    }
    @Published var defaultTaskPriority: Int {
        didSet { defaults.set(defaultTaskPriority, forKey: keyPrefix + "defaultTaskPriority") }
    }
    @Published var showCompletedTasks: Bool {
        didSet { defaults.set(showCompletedTasks, forKey: keyPrefix + "showCompletedTasks") }
    }
    @Published var upcomingDaysRange: Int {
        didSet { defaults.set(upcomingDaysRange, forKey: keyPrefix + "upcomingDaysRange") }
    }
    @Published var dailyReminderEnabled: Bool {
        didSet { defaults.set(dailyReminderEnabled, forKey: keyPrefix + "dailyReminderEnabled") }
    }
    @Published var dailyReminderTime: Int {
        didSet { defaults.set(dailyReminderTime, forKey: keyPrefix + "dailyReminderTime") }
    }

    private init() {
        // Load from UserDefaults with defaults
        self.theme = defaults.string(forKey: keyPrefix + "theme") ?? "system"
        self.defaultTaskPriority = defaults.object(forKey: keyPrefix + "defaultTaskPriority") as? Int ?? 1
        self.showCompletedTasks = defaults.object(forKey: keyPrefix + "showCompletedTasks") as? Bool ?? true
        self.upcomingDaysRange = defaults.object(forKey: keyPrefix + "upcomingDaysRange") as? Int ?? 7
        self.dailyReminderEnabled = defaults.object(forKey: keyPrefix + "dailyReminderEnabled") as? Bool ?? false
        self.dailyReminderTime = defaults.object(forKey: keyPrefix + "dailyReminderTime") as? Int ?? 540
    }
}

// MARK: - Task Priority Helpers

extension SettingsManager {
    var defaultPriority: TaskPriority {
        TaskPriority(rawValue: defaultTaskPriority) ?? .medium
    }

    func setDefaultPriority(_ priority: TaskPriority) {
        defaultTaskPriority = priority.rawValue
    }
}
