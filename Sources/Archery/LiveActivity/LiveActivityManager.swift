import Foundation
import SwiftUI

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

@available(iOS 16.1, *)
public protocol LiveActivityManaging {
    associatedtype Attributes: ActivityAttributes
    
    func start(attributes: Attributes, contentState: Attributes.ContentState) async throws -> String
    func update(id: String, contentState: Attributes.ContentState) async throws
    func end(id: String, contentState: Attributes.ContentState?, dismissalPolicy: ActivityUIDismissalPolicy) async throws
    func getActivity(id: String) -> Activity<Attributes>?
    func getAllActivities() -> [Activity<Attributes>]
}

@available(iOS 16.1, *)
public class LiveActivityManager<Attributes: ActivityAttributes>: ObservableObject, LiveActivityManaging {
    @Published public private(set) var activities: [String: Activity<Attributes>] = [:]
    private let staleTimeout: TimeInterval
    private let allowsMultiple: Bool
    
    public init(
        staleTimeout: TimeInterval = 14400,
        allowsMultiple: Bool = false
    ) {
        self.staleTimeout = staleTimeout
        self.allowsMultiple = allowsMultiple
        observeActivities()
    }
    
    public func start(
        attributes: Attributes,
        contentState: Attributes.ContentState
    ) async throws -> String {
        if !allowsMultiple {
            for activity in Activity<Attributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        
        let activityContent = ActivityContent(
            state: contentState,
            staleDate: Date().addingTimeInterval(staleTimeout)
        )
        
        let activity = try Activity.request(
            attributes: attributes,
            content: activityContent
        )
        
        activities[activity.id] = activity
        return activity.id
    }
    
    public func update(
        id: String,
        contentState: Attributes.ContentState
    ) async throws {
        guard let activity = activities[id] else {
            throw LiveActivityError.activityNotFound(id)
        }
        
        let updatedContent = ActivityContent(
            state: contentState,
            staleDate: Date().addingTimeInterval(staleTimeout)
        )
        
        await activity.update(updatedContent)
    }
    
    public func end(
        id: String,
        contentState: Attributes.ContentState? = nil,
        dismissalPolicy: ActivityUIDismissalPolicy = .default
    ) async throws {
        guard let activity = activities[id] else {
            throw LiveActivityError.activityNotFound(id)
        }
        
        let finalContent: ActivityContent<Attributes.ContentState>? = contentState.map { state in
            ActivityContent(
                state: state,
                staleDate: Date()
            )
        }
        
        await activity.end(finalContent, dismissalPolicy: dismissalPolicy)
        activities[id] = nil
    }
    
    public func getActivity(id: String) -> Activity<Attributes>? {
        activities[id]
    }
    
    public func getAllActivities() -> [Activity<Attributes>] {
        Array(activities.values)
    }
    
    private func observeActivities() {
        Task {
            for activity in Activity<Attributes>.activities {
                activities[activity.id] = activity
                
                Task {
                    for await state in activity.activityStateUpdates {
                        if state == .ended || state == .dismissed {
                            await MainActor.run {
                                activities[activity.id] = nil
                            }
                        }
                    }
                }
            }
        }
    }
}

@available(iOS 16.1, *)
public struct LiveActivityConfiguration<Attributes: ActivityAttributes> {
    public let attributes: Attributes
    public let contentState: Attributes.ContentState
    public let staleDate: Date?
    public let relevanceScore: Float?
    
    public init(
        attributes: Attributes,
        contentState: Attributes.ContentState,
        staleDate: Date? = nil,
        relevanceScore: Float? = nil
    ) {
        self.attributes = attributes
        self.contentState = contentState
        self.staleDate = staleDate
        self.relevanceScore = relevanceScore
    }
}

@available(iOS 16.1, *)
public struct LiveActivityFixture<Attributes: ActivityAttributes> {
    public let name: String
    public let attributes: Attributes
    public let contentStates: [Attributes.ContentState]
    public let updateInterval: TimeInterval
    
    public init(
        name: String,
        attributes: Attributes,
        contentStates: [Attributes.ContentState],
        updateInterval: TimeInterval = 60
    ) {
        self.name = name
        self.attributes = attributes
        self.contentStates = contentStates
        self.updateInterval = updateInterval
    }
}

#if DEBUG
@available(iOS 16.1, *)
public class MockLiveActivityManager<Attributes: ActivityAttributes>: ObservableObject, LiveActivityManaging {
    @Published public var activities: [String: MockActivity<Attributes>] = [:]
    private var nextId = 0
    
    public init() {}
    
    public func start(
        attributes: Attributes,
        contentState: Attributes.ContentState
    ) async throws -> String {
        let id = "mock-\(nextId)"
        nextId += 1
        
        let activity = MockActivity(
            id: id,
            attributes: attributes,
            contentState: contentState
        )
        activities[id] = activity
        return id
    }
    
    public func update(
        id: String,
        contentState: Attributes.ContentState
    ) async throws {
        guard let activity = activities[id] else {
            throw LiveActivityError.activityNotFound(id)
        }
        activity.contentState = contentState
    }
    
    public func end(
        id: String,
        contentState: Attributes.ContentState? = nil,
        dismissalPolicy: ActivityUIDismissalPolicy = .default
    ) async throws {
        guard activities[id] != nil else {
            throw LiveActivityError.activityNotFound(id)
        }
        activities[id] = nil
    }
    
    public func getActivity(id: String) -> Activity<Attributes>? {
        nil
    }
    
    public func getAllActivities() -> [Activity<Attributes>] {
        []
    }
}

@available(iOS 16.1, *)
public class MockActivity<Attributes: ActivityAttributes> {
    public let id: String
    public let attributes: Attributes
    public var contentState: Attributes.ContentState
    
    init(id: String, attributes: Attributes, contentState: Attributes.ContentState) {
        self.id = id
        self.attributes = attributes
        self.contentState = contentState
    }
}
#endif

#endif

public enum LiveActivityError: LocalizedError {
    case activityNotFound(String)
    case tooManyActivities
    case notSupported
    
    public var errorDescription: String? {
        switch self {
        case .activityNotFound(let id):
            return "Live Activity with ID '\(id)' not found"
        case .tooManyActivities:
            return "Maximum number of Live Activities reached"
        case .notSupported:
            return "Live Activities are not supported on this device"
        }
    }
}