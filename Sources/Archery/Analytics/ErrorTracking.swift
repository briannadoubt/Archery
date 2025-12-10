import Foundation

// MARK: - Archery Error Tracking
//
// Central error tracking utility that integrates with ArcheryAnalytics.
// Used internally by framework layers to automatically track errors.

/// Central error tracker for Archery framework
public struct ArcheryErrorTracker: Sendable {
    private init() {}

    /// Track an error with domain and context
    ///
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - domain: Error domain (e.g., "repository", "network", "storekit")
    ///   - context: Additional context (e.g., function name, endpoint)
    ///   - file: Source file (auto-captured)
    ///   - line: Source line (auto-captured)
    @MainActor
    public static func track(
        _ error: Error,
        domain: String,
        context: String? = nil,
        file: String = #file,
        line: Int = #line
    ) {
        let config = ArcheryAnalyticsConfiguration.shared
        guard config.enabledCategories.contains(.errors) else { return }

        let nsError = error as NSError
        let errorCode: String
        let errorMessage: String

        // Extract meaningful error info
        if let localizedError = error as? LocalizedError {
            errorCode = String(nsError.code)
            errorMessage = localizedError.errorDescription ?? error.localizedDescription
        } else {
            errorCode = String(nsError.code)
            errorMessage = error.localizedDescription
        }

        // Build context string
        let contextString: String?
        if let context {
            contextString = context
        } else {
            let fileName = URL(fileURLWithPath: file).lastPathComponent
            contextString = "\(fileName):\(line)"
        }

        let event = ArcheryEvent.errorOccurred(
            domain: domain,
            code: errorCode,
            message: errorMessage,
            context: contextString
        )

        config.track(event)
    }

    /// Track a repository error
    @MainActor
    public static func trackRepositoryError(
        _ error: Error,
        operation: String,
        entityType: String? = nil
    ) {
        var context = operation
        if let entityType {
            context = "\(entityType).\(operation)"
        }
        track(error, domain: "repository", context: context)
    }

    /// Track a network error
    @MainActor
    public static func trackNetworkError(
        _ error: Error,
        endpoint: String,
        method: String = "GET"
    ) {
        track(error, domain: "network", context: "\(method) \(endpoint)")
    }

    /// Track a StoreKit error
    @MainActor
    public static func trackStoreKitError(
        _ error: Error,
        operation: String,
        productId: String? = nil
    ) {
        var context = operation
        if let productId {
            context = "\(operation):\(productId)"
        }
        track(error, domain: "storekit", context: context)
    }

    /// Track an intent error
    @MainActor
    public static func trackIntentError(
        _ error: Error,
        intentName: String
    ) {
        track(error, domain: "intent", context: intentName)
    }

    /// Track a navigation error
    @MainActor
    public static func trackNavigationError(
        _ error: Error,
        route: String? = nil
    ) {
        track(error, domain: "navigation", context: route)
    }
}

// MARK: - Error Domain Constants

extension ArcheryErrorTracker {
    /// Predefined error domains
    public enum Domain: String, Sendable {
        case repository
        case network
        case storekit
        case navigation
        case intent
        case validation
        case persistence
        case authentication
    }
}
