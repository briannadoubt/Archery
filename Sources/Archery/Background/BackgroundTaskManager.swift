import Foundation
import BackgroundTasks

#if canImport(BackgroundTasks)

// MARK: - Background Task Manager

@available(iOS 13.0, macOS 10.15, *)
public final class BackgroundTaskManager: ObservableObject {
    
    public static let shared = BackgroundTaskManager()
    
    private var registeredTasks: Set<String> = []
    private var taskHandlers: [String: BackgroundTaskHandler] = [:]
    private let container: EnvContainer
    
    private init(container: EnvContainer = .shared) {
        self.container = container
    }
    
    // MARK: - Task Registration
    
    /// Register background task types
    public func registerBackgroundTasks() {
        for taskId in registeredTasks {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
                self.handleBackgroundTask(task)
            }
        }
    }
    
    /// Register a specific background task
    public func register<Handler: BackgroundTaskHandler>(
        taskId: String,
        handler: Handler.Type
    ) {
        registeredTasks.insert(taskId)
        taskHandlers[taskId] = handler.init()
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            self.handleBackgroundTask(task)
        }
    }
    
    // MARK: - Task Scheduling
    
    /// Schedule a background refresh task
    public func scheduleAppRefresh(
        identifier: String,
        earliestBeginDate: Date? = nil
    ) throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        
        try BGTaskScheduler.shared.submit(request)
    }
    
    /// Schedule a background processing task
    public func scheduleProcessingTask(
        identifier: String,
        earliestBeginDate: Date? = nil,
        requiresNetworkConnectivity: Bool = false,
        requiresExternalPower: Bool = false
    ) throws {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        request.requiresNetworkConnectivity = requiresNetworkConnectivity
        request.requiresExternalPower = requiresExternalPower
        
        try BGTaskScheduler.shared.submit(request)
    }
    
    /// Cancel all pending tasks
    public func cancelAllPendingTasks() {
        BGTaskScheduler.shared.cancelAllTaskRequests()
    }
    
    /// Cancel specific task
    public func cancelTask(identifier: String) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
    
    // MARK: - Task Execution
    
    private func handleBackgroundTask(_ task: BGTask) {
        guard let handler = taskHandlers[task.identifier] else {
            task.setTaskCompleted(success: false)
            return
        }
        
        task.expirationHandler = {
            handler.handleExpiration()
            task.setTaskCompleted(success: false)
        }
        
        Task {
            do {
                try await handler.execute(with: container)
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
            
            // Schedule next occurrence
            try? await handler.scheduleNext()
        }
    }
}

// MARK: - Background Task Handler Protocol

@available(iOS 13.0, macOS 10.15, *)
public protocol BackgroundTaskHandler: AnyObject {
    var identifier: String { get }
    
    init()
    
    func execute(with container: EnvContainer) async throws
    func handleExpiration()
    func scheduleNext() async throws
}

// MARK: - Common Background Tasks

@available(iOS 13.0, macOS 10.15, *)
public final class DataSyncTask: BackgroundTaskHandler {
    public let identifier = "com.archery.data-sync"
    
    public init() {}
    
    public func execute(with container: EnvContainer) async throws {
        // Sync critical data
        guard let repositories = container.resolve([any DataRepository].self) else {
            throw BackgroundTaskError.repositoriesUnavailable
        }
        
        for repository in repositories {
            try await repository.syncIfNeeded()
        }
        
        // Update widgets after sync
        WidgetTimelineManager.shared.reloadAll()
    }
    
    public func handleExpiration() {
        // Save current progress
        UserDefaults.standard.set(Date(), forKey: "last_sync_attempt")
    }
    
    public func scheduleNext() async throws {
        let nextSync = Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date()
        try BackgroundTaskManager.shared.scheduleAppRefresh(
            identifier: identifier,
            earliestBeginDate: nextSync
        )
    }
}

@available(iOS 13.0, macOS 10.15, *)
public final class CacheCleanupTask: BackgroundTaskHandler {
    public let identifier = "com.archery.cache-cleanup"
    
    public init() {}
    
    public func execute(with container: EnvContainer) async throws {
        // Clean up old cache files
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let cacheURL = cacheDirectory else { return }
        
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        
        guard let enumerator = fileManager.enumerator(
            at: cacheURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else { return }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                
                if let isDirectory = resourceValues.isDirectory, !isDirectory,
                   let modificationDate = resourceValues.contentModificationDate,
                   modificationDate < cutoffDate {
                    try fileManager.removeItem(at: fileURL)
                }
            } catch {
                // Continue with other files
                continue
            }
        }
    }
    
    public func handleExpiration() {
        // Nothing to save
    }
    
    public func scheduleNext() async throws {
        let nextCleanup = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        try BackgroundTaskManager.shared.scheduleProcessingTask(
            identifier: identifier,
            earliestBeginDate: nextCleanup
        )
    }
}

@available(iOS 13.0, macOS 10.15, *)
public final class AnalyticsUploadTask: BackgroundTaskHandler {
    public let identifier = "com.archery.analytics-upload"
    
    public init() {}
    
    public func execute(with container: EnvContainer) async throws {
        guard let analytics = AnalyticsManager.shared else { return }
        
        try await analytics.uploadPendingEvents()
    }
    
    public func handleExpiration() {
        // Mark upload as interrupted
        UserDefaults.standard.set(true, forKey: "analytics_upload_interrupted")
    }
    
    public func scheduleNext() async throws {
        let nextUpload = Calendar.current.date(byAdding: .hour, value: 4, to: Date()) ?? Date()
        try BackgroundTaskManager.shared.scheduleAppRefresh(
            identifier: identifier,
            earliestBeginDate: nextUpload
        )
    }
}

// MARK: - Background Task Errors

@available(iOS 13.0, macOS 10.15, *)
public enum BackgroundTaskError: Error, LocalizedError {
    case repositoriesUnavailable
    case networkUnavailable
    case taskExpired
    case schedulingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .repositoriesUnavailable:
            return "Data repositories are not available"
        case .networkUnavailable:
            return "Network connection is not available"
        case .taskExpired:
            return "Background task expired"
        case .schedulingFailed(let reason):
            return "Failed to schedule background task: \(reason)"
        }
    }
}

// MARK: - Background Task Macro

/// Generates a background task handler with repository integration
@attached(extension, conformances: BackgroundTaskHandler, names: named(execute), named(scheduleNext))
@attached(member, names: arbitrary)
public macro BackgroundTask(
    identifier: String,
    repositories: [String] = [],
    interval: String = "hour",
    requiresNetwork: Bool = false
) = #externalMacro(module: "ArcheryMacros", type: "BackgroundTaskMacro")

// MARK: - Repository Extension for Background Tasks

@available(iOS 13.0, macOS 10.15, *)
public extension DataRepository {
    func syncIfNeeded() async throws {
        // Default implementation - override in specific repositories
        let lastSync = UserDefaults.standard.object(forKey: "last_sync_\(Self.self)") as? Date ?? .distantPast
        let sixHoursAgo = Date().addingTimeInterval(-6 * 60 * 60)
        
        if lastSync < sixHoursAgo {
            try await performBackgroundSync()
            UserDefaults.standard.set(Date(), forKey: "last_sync_\(Self.self)")
        }
    }
    
    func performBackgroundSync() async throws {
        // Override in specific repositories
    }
}

// MARK: - Background Context

@available(iOS 13.0, macOS 10.15, *)
public struct BackgroundContext {
    public let remainingTime: TimeInterval
    public let isExpired: Bool
    public let container: EnvContainer
    
    internal init(remainingTime: TimeInterval, isExpired: Bool, container: EnvContainer) {
        self.remainingTime = remainingTime
        self.isExpired = isExpired
        self.container = container
    }
}

// MARK: - Background Task Coordinator

@available(iOS 13.0, macOS 10.15, *)
public final class BackgroundTaskCoordinator {
    
    public static let shared = BackgroundTaskCoordinator()
    
    private let manager = BackgroundTaskManager.shared
    private var isConfigured = false
    
    private init() {}
    
    /// Configure all default background tasks
    public func configure() {
        guard !isConfigured else { return }
        
        // Register default tasks
        manager.register(taskId: "com.archery.data-sync", handler: DataSyncTask.self)
        manager.register(taskId: "com.archery.cache-cleanup", handler: CacheCleanupTask.self)
        manager.register(taskId: "com.archery.analytics-upload", handler: AnalyticsUploadTask.self)
        
        manager.registerBackgroundTasks()
        isConfigured = true
    }
    
    /// Schedule initial background tasks
    public func scheduleInitialTasks() {
        do {
            // Schedule data sync for 1 hour from now
            try manager.scheduleAppRefresh(
                identifier: "com.archery.data-sync",
                earliestBeginDate: Date().addingTimeInterval(3600)
            )
            
            // Schedule cache cleanup for tonight
            let tonight = Calendar.current.date(bySettingHour: 2, minute: 0, second: 0, of: Date().addingTimeInterval(86400)) ?? Date()
            try manager.scheduleProcessingTask(
                identifier: "com.archery.cache-cleanup",
                earliestBeginDate: tonight
            )
            
            // Schedule analytics upload
            try manager.scheduleAppRefresh(
                identifier: "com.archery.analytics-upload",
                earliestBeginDate: Date().addingTimeInterval(1800) // 30 minutes
            )
            
        } catch {
            print("Failed to schedule background tasks: \(error)")
        }
    }
    
    /// Get status of background tasks
    public func getTaskStatus() async -> [BackgroundTaskStatus] {
        var statuses: [BackgroundTaskStatus] = []
        
        do {
            let pendingRequests = try await BGTaskScheduler.shared.pendingTaskRequests()
            
            for request in pendingRequests {
                statuses.append(BackgroundTaskStatus(
                    identifier: request.identifier,
                    earliestBeginDate: request.earliestBeginDate,
                    isScheduled: true
                ))
            }
        } catch {
            // Unable to get pending requests
        }
        
        return statuses
    }
}

public struct BackgroundTaskStatus {
    public let identifier: String
    public let earliestBeginDate: Date?
    public let isScheduled: Bool
    
    public init(identifier: String, earliestBeginDate: Date?, isScheduled: Bool) {
        self.identifier = identifier
        self.earliestBeginDate = earliestBeginDate
        self.isScheduled = isScheduled
    }
}

#endif