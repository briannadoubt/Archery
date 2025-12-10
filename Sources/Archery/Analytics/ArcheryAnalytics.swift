import Foundation

// MARK: - Archery Framework Analytics
//
// This module provides automatic analytics tracking baked into Archery's framework layers.
// Apps receive analytics "for free" by simply setting an event handler.
//
// Usage:
//   ArcheryAnalyticsConfiguration.shared.eventHandler = { event in
//       // Forward to your analytics provider (Segment, Amplitude, etc.)
//       MyAnalytics.track(event.name, properties: event.properties)
//   }

/// Framework-level analytics events automatically tracked by Archery
public enum ArcheryEvent: Sendable, Equatable {
    // MARK: - Navigation Events

    /// Fired when a route is navigated to
    case screenViewed(route: String, style: String, tab: String?)

    /// Fired when a flow begins
    case flowStarted(flowType: String, flowId: String)

    /// Fired when a flow step is completed
    case flowStepCompleted(flowType: String, flowId: String, step: Int, stepName: String)

    /// Fired when a flow completes successfully
    case flowCompleted(flowType: String, flowId: String, totalSteps: Int)

    /// Fired when a flow is cancelled/abandoned
    case flowAbandoned(flowType: String, flowId: String, atStep: Int)

    // MARK: - Repository CRUD Events

    /// Fired when an entity is created via repository
    case entityCreated(entityType: String, entityId: String)

    /// Fired when an entity is updated via repository
    case entityUpdated(entityType: String, entityId: String)

    /// Fired when an entity is deleted via repository
    case entityDeleted(entityType: String, entityId: String)

    /// Fired when entities are fetched via repository
    case entityFetched(entityType: String, count: Int, durationMs: Double)

    // MARK: - Monetization Events

    /// Fired when a paywall is displayed
    case paywallViewed(source: String, requiredEntitlement: String?)

    /// Fired when a purchase flow begins
    case purchaseStarted(productId: String, price: Double?)

    /// Fired when a purchase completes successfully
    case purchaseCompleted(productId: String, price: Double, transactionId: String?)

    /// Fired when a purchase fails
    case purchaseFailed(productId: String, errorCode: String, errorMessage: String)

    /// Fired when subscriptions are restored
    case subscriptionRestored(productIds: [String])

    /// Fired when navigation is blocked due to missing entitlement
    case entitlementBlocked(route: String, required: String)

    // MARK: - Authentication Events

    /// Fired when authentication starts
    case authStarted(method: String)

    /// Fired when authentication succeeds
    case authCompleted(method: String, hasRefreshToken: Bool)

    /// Fired when authentication fails
    case authFailed(method: String, errorCode: String, errorMessage: String)

    /// Fired when token is refreshed
    case authTokenRefreshed

    /// Fired when token refresh fails
    case authRefreshFailed(errorCode: String, errorMessage: String)

    /// Fired when user signs out
    case authSignedOut

    // MARK: - Error Events

    /// Fired when an error occurs in any framework layer
    case errorOccurred(domain: String, code: String, message: String, context: String?)
}

// MARK: - Event Properties

extension ArcheryEvent {
    /// Event name in snake_case format for analytics providers
    public var name: String {
        switch self {
        case .screenViewed: return "screen_viewed"
        case .flowStarted: return "flow_started"
        case .flowStepCompleted: return "flow_step_completed"
        case .flowCompleted: return "flow_completed"
        case .flowAbandoned: return "flow_abandoned"
        case .entityCreated: return "entity_created"
        case .entityUpdated: return "entity_updated"
        case .entityDeleted: return "entity_deleted"
        case .entityFetched: return "entity_fetched"
        case .paywallViewed: return "paywall_viewed"
        case .purchaseStarted: return "purchase_started"
        case .purchaseCompleted: return "purchase_completed"
        case .purchaseFailed: return "purchase_failed"
        case .subscriptionRestored: return "subscription_restored"
        case .entitlementBlocked: return "entitlement_blocked"
        case .authStarted: return "auth_started"
        case .authCompleted: return "auth_completed"
        case .authFailed: return "auth_failed"
        case .authTokenRefreshed: return "auth_token_refreshed"
        case .authRefreshFailed: return "auth_refresh_failed"
        case .authSignedOut: return "auth_signed_out"
        case .errorOccurred: return "error_occurred"
        }
    }

    /// Event properties as a dictionary for analytics providers
    public var properties: [String: Any] {
        switch self {
        case .screenViewed(let route, let style, let tab):
            var props: [String: Any] = ["route": route, "style": style]
            if let tab { props["tab"] = tab }
            return props

        case .flowStarted(let flowType, let flowId):
            return ["flow_type": flowType, "flow_id": flowId]

        case .flowStepCompleted(let flowType, let flowId, let step, let stepName):
            return ["flow_type": flowType, "flow_id": flowId, "step": step, "step_name": stepName]

        case .flowCompleted(let flowType, let flowId, let totalSteps):
            return ["flow_type": flowType, "flow_id": flowId, "total_steps": totalSteps]

        case .flowAbandoned(let flowType, let flowId, let atStep):
            return ["flow_type": flowType, "flow_id": flowId, "abandoned_at_step": atStep]

        case .entityCreated(let entityType, let entityId):
            return ["entity_type": entityType, "entity_id": entityId]

        case .entityUpdated(let entityType, let entityId):
            return ["entity_type": entityType, "entity_id": entityId]

        case .entityDeleted(let entityType, let entityId):
            return ["entity_type": entityType, "entity_id": entityId]

        case .entityFetched(let entityType, let count, let durationMs):
            return ["entity_type": entityType, "count": count, "duration_ms": durationMs]

        case .paywallViewed(let source, let requiredEntitlement):
            var props: [String: Any] = ["source": source]
            if let req = requiredEntitlement { props["required_entitlement"] = req }
            return props

        case .purchaseStarted(let productId, let price):
            var props: [String: Any] = ["product_id": productId]
            if let price { props["price"] = price }
            return props

        case .purchaseCompleted(let productId, let price, let transactionId):
            var props: [String: Any] = ["product_id": productId, "price": price]
            if let txId = transactionId { props["transaction_id"] = txId }
            return props

        case .purchaseFailed(let productId, let errorCode, let errorMessage):
            return ["product_id": productId, "error_code": errorCode, "error_message": errorMessage]

        case .subscriptionRestored(let productIds):
            return ["product_ids": productIds, "count": productIds.count]

        case .entitlementBlocked(let route, let required):
            return ["route": route, "required_entitlement": required]

        case .authStarted(let method):
            return ["method": method]

        case .authCompleted(let method, let hasRefreshToken):
            return ["method": method, "has_refresh_token": hasRefreshToken]

        case .authFailed(let method, let errorCode, let errorMessage):
            return ["method": method, "error_code": errorCode, "error_message": errorMessage]

        case .authTokenRefreshed:
            return [:]

        case .authRefreshFailed(let errorCode, let errorMessage):
            return ["error_code": errorCode, "error_message": errorMessage]

        case .authSignedOut:
            return [:]

        case .errorOccurred(let domain, let code, let message, let context):
            var props: [String: Any] = ["domain": domain, "code": code, "message": message]
            if let ctx = context { props["context"] = ctx }
            return props
        }
    }

    /// Category this event belongs to
    public var category: ArcheryAnalyticsConfiguration.EventCategory {
        switch self {
        case .screenViewed, .flowStarted, .flowStepCompleted, .flowCompleted, .flowAbandoned:
            return .navigation
        case .entityCreated, .entityUpdated, .entityDeleted, .entityFetched:
            return .repository
        case .paywallViewed, .purchaseStarted, .purchaseCompleted, .purchaseFailed,
             .subscriptionRestored, .entitlementBlocked:
            return .monetization
        case .authStarted, .authCompleted, .authFailed, .authTokenRefreshed,
             .authRefreshFailed, .authSignedOut:
            return .authentication
        case .errorOccurred:
            return .errors
        }
    }
}

// MARK: - Analytics Configuration

/// Configuration for Archery's automatic analytics tracking
@MainActor
public final class ArcheryAnalyticsConfiguration: Sendable {
    /// Shared configuration instance
    public static let shared = ArcheryAnalyticsConfiguration()

    /// Handler called for every framework event
    /// Set this to forward events to your analytics provider
    public var eventHandler: (@Sendable (ArcheryEvent) -> Void)?

    /// Categories of events to track (defaults to all)
    public var enabledCategories: Set<EventCategory> = Set(EventCategory.allCases)

    private init() {}

    /// Event categories that can be enabled/disabled
    public enum EventCategory: String, CaseIterable, Sendable {
        case navigation
        case repository
        case monetization
        case authentication
        case errors
    }

    /// Track an event if its category is enabled
    public func track(_ event: ArcheryEvent) {
        guard enabledCategories.contains(event.category) else { return }
        eventHandler?(event)
    }

    /// Convenience to disable specific categories
    public func disable(_ categories: EventCategory...) {
        for category in categories {
            enabledCategories.remove(category)
        }
    }

    /// Convenience to enable specific categories
    public func enable(_ categories: EventCategory...) {
        for category in categories {
            enabledCategories.insert(category)
        }
    }

    /// Reset to tracking all categories
    public func enableAll() {
        enabledCategories = Set(EventCategory.allCases)
    }
}

// MARK: - Helper Extensions

extension PresentationStyle {
    /// Analytics-friendly name for presentation style
    public var analyticsName: String {
        switch self {
        case .push: return "push"
        case .replace: return "replace"
        case .sheet: return "sheet"
        case .fullScreen: return "fullscreen"
        case .popover: return "popover"
        case .window: return "window"
        case .tab: return "tab"
        #if os(visionOS)
        case .immersiveSpace: return "immersive_space"
        #endif
        #if os(macOS)
        case .settingsPane: return "settings"
        case .inspector: return "inspector"
        #endif
        }
    }
}
