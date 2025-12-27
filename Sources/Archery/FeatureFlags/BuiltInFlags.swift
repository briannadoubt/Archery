import Foundation

// MARK: - Built-in Framework Feature Flags

/// Built-in feature flags for Archery framework functionality.
/// These flags control framework-level behavior and can be overridden at runtime.
public enum BuiltInFlags {
    // MARK: - Performance Tracing

    /// Enables runtime performance tracing for macro-generated operations.
    /// When enabled, database queries, API requests, and other operations
    /// will emit spans to the observability system.
    ///
    /// **Default: OFF** - Must be explicitly enabled to avoid overhead in production.
    ///
    /// Usage:
    /// ```swift
    /// // Enable performance tracing
    /// FeatureFlagManager.shared.override(BuiltInFlags.PerformanceTracingFlag.self, with: true)
    ///
    /// // Check if enabled
    /// if FeatureFlagManager.shared.isEnabled(for: BuiltInFlags.PerformanceTracingFlag.self) {
    ///     // Tracing is active
    /// }
    /// ```
    public struct PerformanceTracingFlag: FeatureFlag, Sendable {
        public typealias Value = Bool

        public static var key: String { "archery.performance-tracing" }

        public static var defaultValue: Value { false }

        public static var description: String {
            "Enable runtime performance tracing for macro-generated operations"
        }
    }

    // MARK: - Analytics

    /// Controls whether framework-level analytics events are emitted.
    /// Affects events from @Persistable, @APIClient, and @DatabaseRepository.
    public struct FrameworkAnalyticsFlag: FeatureFlag, Sendable {
        public typealias Value = Bool

        public static var key: String { "archery.framework-analytics" }

        public static var defaultValue: Value { true }

        public static var description: String {
            "Enable framework-level analytics events"
        }
    }

    // MARK: - Debug

    /// Enables verbose logging for macro-generated code.
    /// Useful for debugging issues with generated repositories and clients.
    public struct VerboseLoggingFlag: FeatureFlag, Sendable {
        public typealias Value = Bool

        public static var key: String { "archery.verbose-logging" }

        public static var defaultValue: Value { false }

        public static var description: String {
            "Enable verbose logging for debugging macro-generated code"
        }
    }
}

// MARK: - Convenience Access

extension BuiltInFlags {
    /// All built-in feature flags for iteration in debug UI
    public static var allFlags: [any FeatureFlag.Type] {
        [
            PerformanceTracingFlag.self,
            FrameworkAnalyticsFlag.self,
            VerboseLoggingFlag.self
        ]
    }

    /// Human-readable names for each flag
    public static func displayName(for key: String) -> String {
        switch key {
        case "archery.performance-tracing": return "Performance Tracing"
        case "archery.framework-analytics": return "Framework Analytics"
        case "archery.verbose-logging": return "Verbose Logging"
        default: return key
        }
    }
}
