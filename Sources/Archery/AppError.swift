import Foundation

/// A lightweight error type for surfacing user-facing copy while keeping
/// redacted metadata for logging and analytics.
public struct AppError: Error, Equatable, CustomStringConvertible, Identifiable, Sendable {
    public enum Category: String, Sendable {
        case network
        case decoding
        case validation
        case unknown
    }

    /// Message that is safe to show to end users.
    public let message: String
    /// Optional title for alerts or banners.
    public let title: String
    /// Bucket used for grouping and dashboards.
    public let category: Category
    /// Internal-only metadata. Values are always redacted before emission.
    public let metadata: [String: String]
    /// Optional underlying error for debugging.
    public let underlying: Error?
    private let redactor: @Sendable (String) -> String

    public init(
        title: String = "Something went wrong",
        message: String,
        category: Category = .unknown,
        metadata: [String: String] = [:],
        underlying: Error? = nil,
        redactor: @escaping @Sendable (String) -> String = AppError.defaultRedactor
    ) {
        self.title = title
        self.message = message
        self.category = category
        self.metadata = metadata
        self.underlying = underlying
        self.redactor = redactor
    }

    public var description: String { "\(title): \(message)" }
    public var id: String { "\(title)|\(message)" }

    /// Convenience surface for presenting to the UI layer.
    public var alertState: AlertState {
        AlertState(title: title, message: message)
    }

    /// Generates a redacted payload suitable for structured logging.
    public func logPayload() -> LogPayload {
        let redactedMetadata = metadata.mapValues(redactor)
        let underlyingDescription = underlying.map { redactor(String(describing: $0)) }
        return LogPayload(
            title: title,
            message: message,
            category: category,
            metadata: redactedMetadata,
            underlying: underlyingDescription
        )
    }

    /// Emits redacted data to analytics sinks.
    public func analyticsPayload() -> AnalyticsPayload {
        AnalyticsPayload(
            title: title,
            message: message,
            category: category
        )
    }

    /// Default redaction replaces the content with a sentinel to avoid PII/secret leaks.
    public static func defaultRedactor(_ value: String) -> String { value.isEmpty ? value : "[REDACTED]" }

    public static func == (lhs: AppError, rhs: AppError) -> Bool {
        lhs.title == rhs.title &&
            lhs.message == rhs.message &&
            lhs.category == rhs.category
    }
}

public extension AppError {
    struct LogPayload: Sendable {
        public let title: String
        public let message: String
        public let category: Category
        public let metadata: [String: String]
        public let underlying: String?
    }

    struct AnalyticsPayload: Sendable {
        public let title: String
        public let message: String
        public let category: Category
    }

    /// Helper to wrap arbitrary errors with a user-safe message.
    static func wrap(
        _ error: Error,
        fallbackMessage: String = "Please try again.",
        category: Category = .unknown,
        redactor: @escaping @Sendable (String) -> String = AppError.defaultRedactor
    ) -> AppError {
        AppError(
            title: "Something went wrong",
            message: fallbackMessage,
            category: category,
            metadata: ["debug": String(describing: error)],
            underlying: error,
            redactor: redactor
        )
    }
}
