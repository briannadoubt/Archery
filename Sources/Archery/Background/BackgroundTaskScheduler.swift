#if os(iOS) || os(macOS)
@preconcurrency import BackgroundTasks
#endif
import Foundation
import Combine

public protocol BackgroundTaskScheduling: Sendable {
    func register(identifier: String, handler: @escaping @Sendable () async throws -> Void)
    func schedule(identifier: String, at date: Date?) async throws
    func cancel(identifier: String) throws
    func cancelAll()
    func getPendingTasks() async -> [String]
}

@available(iOS 13.0, macOS 11.0, *)
public final class BackgroundTaskScheduler: BackgroundTaskScheduling, @unchecked Sendable {
    public static let shared = BackgroundTaskScheduler()

    private var handlers: [String: @Sendable () async throws -> Void] = [:]
    private var registeredIdentifiers: Set<String> = []
    private let queue = DispatchQueue(label: "com.archery.backgroundtasks", qos: .utility)

    private init() {}

    public func register(
        identifier: String,
        handler: @escaping @Sendable () async throws -> Void
    ) {
        queue.sync {
            handlers[identifier] = handler
            registeredIdentifiers.insert(identifier)
        }
        
        #if os(iOS)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            Task {
                do {
                    try await handler()
                    task.setTaskCompleted(success: true)
                } catch {
                    task.setTaskCompleted(success: false)
                }
            }
        }
        #endif
    }
    
    public func schedule(
        identifier: String,
        at date: Date? = nil
    ) async throws {
        guard registeredIdentifiers.contains(identifier) else {
            throw BackgroundTaskError.unregisteredIdentifier(identifier)
        }
        
        #if os(iOS)
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.earliestBeginDate = date
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        try BGTaskScheduler.shared.submit(request)
        #else
        if let date = date {
            let delay = max(0, date.timeIntervalSinceNow)
            Task {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if let handler = handlers[identifier] {
                    try await handler()
                }
            }
        }
        #endif
    }
    
    public func cancel(identifier: String) throws {
        guard registeredIdentifiers.contains(identifier) else {
            throw BackgroundTaskError.unregisteredIdentifier(identifier)
        }
        
        #if os(iOS)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        #endif
    }
    
    public func cancelAll() {
        #if os(iOS)
        BGTaskScheduler.shared.cancelAllTaskRequests()
        #endif
    }
    
    public func getPendingTasks() async -> [String] {
        #if os(iOS)
        return await withCheckedContinuation { continuation in
            BGTaskScheduler.shared.getPendingTaskRequests { requests in
                let identifiers = requests.map { $0.identifier }
                continuation.resume(returning: identifiers)
            }
        }
        #else
        return []
        #endif
    }
}

public enum BackgroundTaskError: LocalizedError {
    case unregisteredIdentifier(String)
    case taskFailed(String)
    case notSupported
    
    public var errorDescription: String? {
        switch self {
        case .unregisteredIdentifier(let id):
            return "Task identifier '\(id)' is not registered"
        case .taskFailed(let reason):
            return "Background task failed: \(reason)"
        case .notSupported:
            return "Background tasks are not supported on this platform"
        }
    }
}

public struct BackgroundTaskConfiguration: Sendable {
    public let identifier: String
    public let interval: TimeInterval
    public let requiresNetworkConnectivity: Bool
    public let requiresExternalPower: Bool
    public let allowsExpensiveNetworkAccess: Bool
    
    public init(
        identifier: String,
        interval: TimeInterval = 900,
        requiresNetworkConnectivity: Bool = false,
        requiresExternalPower: Bool = false,
        allowsExpensiveNetworkAccess: Bool = false
    ) {
        self.identifier = identifier
        self.interval = interval
        self.requiresNetworkConnectivity = requiresNetworkConnectivity
        self.requiresExternalPower = requiresExternalPower
        self.allowsExpensiveNetworkAccess = allowsExpensiveNetworkAccess
    }
}

public protocol BackgroundTaskHandling {
    func performTask() async throws
    func shouldReschedule() -> Bool
    func nextScheduleDate() -> Date?
}

public struct BackgroundTaskManager: Sendable {
    private let scheduler: BackgroundTaskScheduling
    private var configurations: [String: BackgroundTaskConfiguration] = [:]

    public init(scheduler: BackgroundTaskScheduling = BackgroundTaskScheduler.shared) {
        self.scheduler = scheduler
    }

    public mutating func registerTask(
        _ configuration: BackgroundTaskConfiguration,
        handler: @escaping @Sendable () async throws -> Void
    ) {
        configurations[configuration.identifier] = configuration
        scheduler.register(identifier: configuration.identifier, handler: handler)
    }
    
    public func scheduleTask(_ identifier: String) async throws {
        guard let config = configurations[identifier] else {
            throw BackgroundTaskError.unregisteredIdentifier(identifier)
        }
        
        let nextDate = Date().addingTimeInterval(config.interval)
        try await scheduler.schedule(identifier: identifier, at: nextDate)
    }
    
    public func scheduleAllTasks() async throws {
        for identifier in configurations.keys {
            try await scheduleTask(identifier)
        }
    }
}

#if DEBUG
public final class MockBackgroundTaskScheduler: BackgroundTaskScheduling, @unchecked Sendable {
    public var handlers: [String: @Sendable () async throws -> Void] = [:]
    public var scheduledTasks: [String: Date] = [:]
    public var cancelledTasks: Set<String> = []

    public init() {}

    public func register(identifier: String, handler: @escaping @Sendable () async throws -> Void) {
        handlers[identifier] = handler
    }
    
    public func schedule(identifier: String, at date: Date?) async throws {
        guard handlers[identifier] != nil else {
            throw BackgroundTaskError.unregisteredIdentifier(identifier)
        }
        scheduledTasks[identifier] = date ?? Date()
    }
    
    public func cancel(identifier: String) throws {
        guard handlers[identifier] != nil else {
            throw BackgroundTaskError.unregisteredIdentifier(identifier)
        }
        scheduledTasks[identifier] = nil
        cancelledTasks.insert(identifier)
    }
    
    public func cancelAll() {
        cancelledTasks.formUnion(scheduledTasks.keys)
        scheduledTasks.removeAll()
    }
    
    public func getPendingTasks() async -> [String] {
        Array(scheduledTasks.keys)
    }
    
    public func executeTask(_ identifier: String) async throws {
        guard let handler = handlers[identifier] else {
            throw BackgroundTaskError.unregisteredIdentifier(identifier)
        }
        try await handler()
    }
}
#endif