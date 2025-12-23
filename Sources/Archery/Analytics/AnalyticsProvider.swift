import Foundation

public protocol AnalyticsEvent {
    var eventName: String { get }
    var properties: [String: Any] { get }
    func validate() throws
    func track(with provider: AnalyticsProvider)
    func redactedProperties() -> [String: Any]
}

public protocol AnalyticsProvider: Sendable {
    func track(eventName: String, properties: [String: Any])
    func identify(userId: String, traits: [String: Any])
    func screen(name: String, properties: [String: Any])
    func flush()
}

public enum AnalyticsError: LocalizedError {
    case invalidProperty(String)
    case missingRequiredProperty(String)
    case invalidEventName
    
    public var errorDescription: String? {
        switch self {
        case .invalidProperty(let message):
            return "Invalid property: \(message)"
        case .missingRequiredProperty(let property):
            return "Missing required property: \(property)"
        case .invalidEventName:
            return "Invalid event name"
        }
    }
}

// MARK: - Analytics Manager

@MainActor
@Observable
public final class AnalyticsManager {
    public static let shared = AnalyticsManager()

    public private(set) var isEnabled: Bool = true
    public private(set) var debugMode: Bool = false
    
    private var providers: [any AnalyticsProvider] = []
    private let queue = DispatchQueue(label: "com.archery.analytics", qos: .background)
    
    private init() {}
    
    public func configure(providers: [any AnalyticsProvider], enabled: Bool = true, debugMode: Bool = false) {
        self.providers = providers
        self.isEnabled = enabled
        self.debugMode = debugMode
    }
    
    public func track<Event: AnalyticsEvent>(_ event: Event) {
        guard isEnabled else { return }

        // Validate synchronously before queueing
        do {
            try event.validate()
        } catch {
            print("[Analytics] Failed to validate event: \(error)")
            return
        }

        let eventName = event.eventName
        let properties = debugMode ? event.properties : event.redactedProperties()
        let debug = debugMode
        let providers = self.providers

        Task {
            if debug {
                print("[Analytics] Tracking: \(eventName) with properties: \(properties)")
            }

            for provider in providers {
                provider.track(eventName: eventName, properties: properties)
            }
        }
    }

    /// Track a raw event with name and properties (no validation)
    /// Used for framework-level auto-tracked events
    public func track(_ eventName: String, properties: [String: Any]) {
        guard isEnabled else { return }

        let redactedProperties = debugMode ? properties : redact(properties)
        let debug = debugMode
        let providers = self.providers

        Task {
            if debug {
                print("[Analytics] Tracking: \(eventName) with properties: \(redactedProperties)")
            }

            for provider in providers {
                provider.track(eventName: eventName, properties: redactedProperties)
            }
        }
    }
    
    public func identify(userId: String, traits: [String: Any] = [:]) {
        guard isEnabled else { return }
        
        let redactedTraits = debugMode ? traits : redact(traits)
        let debug = debugMode
        let providers = self.providers
        
        Task {
            if debug {
                print("[Analytics] Identifying user: \(userId) with traits: \(redactedTraits)")
            }
            
            for provider in providers {
                provider.identify(userId: userId, traits: redactedTraits)
            }
        }
    }
    
    public func screen(name: String, properties: [String: Any] = [:]) {
        guard isEnabled else { return }
        
        let redactedProperties = debugMode ? properties : redact(properties)
        let debug = debugMode
        let providers = self.providers
        
        Task {
            if debug {
                print("[Analytics] Screen view: \(name) with properties: \(redactedProperties)")
            }
            
            for provider in providers {
                provider.screen(name: name, properties: redactedProperties)
            }
        }
    }
    
    public func flush() {
        providers.forEach { $0.flush() }
    }
    
    private func redact(_ properties: [String: Any]) -> [String: Any] {
        var redacted = properties
        for (key, value) in redacted {
            if PIIRedactor.isPIIKey(key) {
                redacted[key] = "[REDACTED]"
            } else if let string = value as? String {
                redacted[key] = PIIRedactor.redact(string)
            }
        }
        return redacted
    }
}

// MARK: - Provider Implementations

public final class SegmentProvider: AnalyticsProvider, @unchecked Sendable {
    private let writeKey: String
    private var batchedEvents: [[String: Any]] = []
    private let batchSize: Int = 20
    
    public init(writeKey: String) {
        self.writeKey = writeKey
    }
    
    public func track(eventName: String, properties: [String: Any]) {
        let event: [String: Any] = [
            "type": "track",
            "event": eventName,
            "properties": properties,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        batchedEvents.append(event)
        
        if batchedEvents.count >= batchSize {
            flush()
        }
    }
    
    public func identify(userId: String, traits: [String: Any]) {
        let event: [String: Any] = [
            "type": "identify",
            "userId": userId,
            "traits": traits,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        batchedEvents.append(event)
    }
    
    public func screen(name: String, properties: [String: Any]) {
        let event: [String: Any] = [
            "type": "screen",
            "name": name,
            "properties": properties,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        batchedEvents.append(event)
    }
    
    public func flush() {
        guard !batchedEvents.isEmpty else { return }
        
        // In production, send batch to Segment API
        let batch = batchedEvents
        batchedEvents.removeAll()
        
        #if DEBUG
        print("[Segment] Would send batch of \(batch.count) events")
        #endif
    }
}

public final class AmplitudeProvider: AnalyticsProvider, @unchecked Sendable {
    private let apiKey: String
    private var userId: String?
    
    public init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    public func track(eventName: String, properties: [String: Any]) {
        let event: [String: Any] = [
            "event_type": eventName,
            "event_properties": properties,
            "user_id": userId ?? "anonymous",
            "time": Int(Date().timeIntervalSince1970 * 1000)
        ]
        
        #if DEBUG
        print("[Amplitude] Track: \(event)")
        #endif
    }
    
    public func identify(userId: String, traits: [String: Any]) {
        self.userId = userId
        
        let event: [String: Any] = [
            "user_id": userId,
            "user_properties": traits
        ]
        
        #if DEBUG
        print("[Amplitude] Identify: \(event)")
        #endif
    }
    
    public func screen(name: String, properties: [String: Any]) {
        track(eventName: "Screen Viewed", properties: properties.merging(["screen_name": name]) { $1 })
    }
    
    public func flush() {
        // Amplitude SDK handles batching internally
    }
}

public final class GA4Provider: AnalyticsProvider, @unchecked Sendable {
    private let measurementId: String
    private let apiSecret: String
    
    public init(measurementId: String, apiSecret: String) {
        self.measurementId = measurementId
        self.apiSecret = apiSecret
    }
    
    public func track(eventName: String, properties: [String: Any]) {
        let event: [String: Any] = [
            "name": eventName,
            "params": properties
        ]
        
        #if DEBUG
        print("[GA4] Track: \(event)")
        #endif
    }
    
    public func identify(userId: String, traits: [String: Any]) {
        let event: [String: Any] = [
            "user_id": userId,
            "user_properties": traits.mapValues { ["value": $0] }
        ]
        
        #if DEBUG
        print("[GA4] Identify: \(event)")
        #endif
    }
    
    public func screen(name: String, properties: [String: Any]) {
        track(eventName: "screen_view", properties: properties.merging(["screen_name": name]) { $1 })
    }
    
    public func flush() {
        // GA4 handles batching internally
    }
}

// MARK: - Debug Provider

public final class DebugAnalyticsProvider: AnalyticsProvider, @unchecked Sendable {
    public var trackedEvents: [(name: String, properties: [String: Any])] = []
    public var identifiedUsers: [(userId: String, traits: [String: Any])] = []
    public var screenViews: [(name: String, properties: [String: Any])] = []
    
    public init() {}
    
    public func track(eventName: String, properties: [String: Any]) {
        trackedEvents.append((name: eventName, properties: properties))
    }
    
    public func identify(userId: String, traits: [String: Any]) {
        identifiedUsers.append((userId: userId, traits: traits))
    }
    
    public func screen(name: String, properties: [String: Any]) {
        screenViews.append((name: name, properties: properties))
    }
    
    public func flush() {
        print("[Debug] Tracked \(trackedEvents.count) events, \(identifiedUsers.count) users, \(screenViews.count) screens")
    }
    
    public func reset() {
        trackedEvents.removeAll()
        identifiedUsers.removeAll()
        screenViews.removeAll()
    }
}