import Foundation

// MARK: - Operation Tracer

/// Utility for wrapping operations with performance tracing spans.
/// Respects the `PerformanceTracingFlag` - no-ops when disabled for zero overhead.
///
/// Usage in generated macro code:
/// ```swift
/// func fetchAll() async throws -> [Record] {
///     try await OperationTracer.trace(
///         "fetchAll",
///         category: .database,
///         attributes: ["table": "records"]
///     ) {
///         try await container.read { db in try Record.fetchAll(db) }
///     }
/// }
/// ```
public enum OperationTracer {
    /// Trace category for semantic grouping
    public enum Category: String, Sendable {
        case database
        case network
        case cache
        case migration
        case query
        case custom
    }

    // MARK: - Async Tracing

    /// Trace an async throwing operation with performance measurement.
    /// No-ops when `PerformanceTracingFlag` is disabled.
    @inlinable
    public static func trace<T: Sendable>(
        _ name: String,
        category: Category,
        attributes: [String: String] = [:],
        operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        // Check if tracing is enabled - early exit for zero overhead
        let isEnabled = await isTracingEnabled()
        guard isEnabled else {
            return try await operation()
        }

        let span = await startSpan(name: name, category: category, attributes: attributes)
        do {
            let result = try await operation()
            await endSpan(span, status: .ok)
            return result
        } catch {
            await endSpan(span, status: .error(error))
            throw error
        }
    }

    /// Trace an async non-throwing operation with performance measurement.
    @inlinable
    public static func trace<T: Sendable>(
        _ name: String,
        category: Category,
        attributes: [String: String] = [:],
        operation: @Sendable () async -> T
    ) async -> T {
        let isEnabled = await isTracingEnabled()
        guard isEnabled else {
            return await operation()
        }

        let span = await startSpan(name: name, category: category, attributes: attributes)
        let result = await operation()
        await endSpan(span, status: .ok)
        return result
    }

    // MARK: - Sync Tracing

    /// Trace a synchronous throwing operation with performance measurement.
    /// Must be called from MainActor context.
    @MainActor
    @inlinable
    public static func traceSync<T>(
        _ name: String,
        category: Category,
        attributes: [String: String] = [:],
        operation: () throws -> T
    ) rethrows -> T {
        guard isTracingEnabledSync() else {
            return try operation()
        }

        let span = startSpanSync(name: name, category: category, attributes: attributes)
        do {
            let result = try operation()
            endSpanSync(span, status: .ok)
            return result
        } catch {
            endSpanSync(span, status: .error(error))
            throw error
        }
    }

    /// Trace a synchronous non-throwing operation with performance measurement.
    @MainActor
    @inlinable
    public static func traceSync<T>(
        _ name: String,
        category: Category,
        attributes: [String: String] = [:],
        operation: () -> T
    ) -> T {
        guard isTracingEnabledSync() else {
            return operation()
        }

        let span = startSpanSync(name: name, category: category, attributes: attributes)
        let result = operation()
        endSpanSync(span, status: .ok)
        return result
    }

    // MARK: - Manual Span Management

    /// Manually start a span for custom tracing scenarios.
    /// Call `endSpan(_:status:)` when done.
    public static func startSpan(
        name: String,
        category: Category,
        attributes: [String: String] = [:]
    ) async -> Span? {
        let isEnabled = await isTracingEnabled()
        guard isEnabled else { return nil }

        var allAttributes = attributes
        allAttributes["category"] = category.rawValue

        return await MainActor.run {
            ContextPropagator.shared.startSpan(name: name, attributes: allAttributes)
        }
    }

    /// End a manually started span.
    public static func endSpan(_ span: Span?, status: SpanStatus) async {
        guard let span else { return }
        span.setStatus(status)
        await MainActor.run {
            ContextPropagator.shared.endSpan(span)
        }
    }

    // MARK: - Internal Helpers (usableFromInline for @inlinable functions)

    @MainActor
    @usableFromInline
    static func isTracingEnabledSync() -> Bool {
        FeatureFlagManager.shared.isEnabled(for: BuiltInFlags.PerformanceTracingFlag.self)
    }

    @usableFromInline
    static func isTracingEnabled() async -> Bool {
        await MainActor.run {
            FeatureFlagManager.shared.isEnabled(for: BuiltInFlags.PerformanceTracingFlag.self)
        }
    }

    @MainActor
    @usableFromInline
    static func startSpanSync(
        name: String,
        category: Category,
        attributes: [String: String]
    ) -> Span {
        var allAttributes = attributes
        allAttributes["category"] = category.rawValue
        return ContextPropagator.shared.startSpan(name: name, attributes: allAttributes)
    }

    @MainActor
    @usableFromInline
    static func endSpanSync(_ span: Span, status: SpanStatus) {
        span.setStatus(status)
        ContextPropagator.shared.endSpan(span)
    }
}

// MARK: - Convenience Extensions

public extension OperationTracer {
    /// Record a database operation trace event.
    static func traceDatabase<T: Sendable>(
        _ operation: String,
        table: String,
        action: @Sendable () async throws -> T
    ) async rethrows -> T {
        try await trace(
            operation,
            category: .database,
            attributes: ["table": table, "operation": operation],
            operation: action
        )
    }

    /// Record a network request trace event.
    static func traceNetwork<T: Sendable>(
        method: String,
        path: String,
        action: @Sendable () async throws -> T
    ) async rethrows -> T {
        try await trace(
            "\(method) \(path)",
            category: .network,
            attributes: ["http.method": method, "http.path": path],
            operation: action
        )
    }

    /// Record a cache operation trace event.
    static func traceCache<T: Sendable>(
        _ operation: String,
        key: String,
        hit: Bool? = nil,
        action: @Sendable () async throws -> T
    ) async rethrows -> T {
        var attributes = ["cache.key": key, "operation": operation]
        if let hit {
            attributes["cache.hit"] = hit ? "true" : "false"
        }
        return try await trace(
            "cache.\(operation)",
            category: .cache,
            attributes: attributes,
            operation: action
        )
    }
}

// MARK: - Span Recording for Statistics

/// Allows collection of span statistics for display in the showcase.
public actor SpanStatisticsCollector {
    public static let shared = SpanStatisticsCollector()

    public struct SpanRecord: Sendable, Identifiable {
        public let id = UUID()
        public let name: String
        public let category: String
        public let duration: TimeInterval
        public let timestamp: Date
        public let status: String
        public let attributes: [String: String]
    }

    private var records: [SpanRecord] = []
    private let maxRecords: Int = 1000

    private init() {}

    /// Record a completed span for statistics.
    public func record(span: Span) {
        guard let duration = span.duration else { return }

        let record = SpanRecord(
            name: span.name,
            category: span.attributes["category"] ?? "unknown",
            duration: duration,
            timestamp: span.startTime,
            status: statusString(span.status),
            attributes: span.attributes
        )

        records.append(record)

        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }
    }

    /// Get all recorded spans.
    public func getRecords() -> [SpanRecord] {
        records
    }

    /// Get records filtered by category.
    public func getRecords(category: String) -> [SpanRecord] {
        records.filter { $0.category == category }
    }

    /// Get aggregate statistics.
    public func getStatistics() -> SpanStatistics {
        let grouped = Dictionary(grouping: records) { $0.category }
        var categoryStats: [String: CategoryStatistics] = [:]

        for (category, categoryRecords) in grouped {
            let durations = categoryRecords.map { $0.duration }
            let mean = durations.reduce(0, +) / Double(durations.count)
            let sorted = durations.sorted()
            let p50 = sorted[sorted.count / 2]
            let p95 = sorted[Int(Double(sorted.count) * 0.95)]
            let p99 = sorted[Int(Double(sorted.count) * 0.99)]

            categoryStats[category] = CategoryStatistics(
                count: categoryRecords.count,
                meanDuration: mean,
                p50Duration: p50,
                p95Duration: p95,
                p99Duration: p99,
                minDuration: sorted.first ?? 0,
                maxDuration: sorted.last ?? 0
            )
        }

        return SpanStatistics(
            totalSpans: records.count,
            byCategory: categoryStats
        )
    }

    /// Clear all recorded spans.
    public func clear() {
        records.removeAll()
    }

    private func statusString(_ status: SpanStatus) -> String {
        switch status {
        case .unset: return "unset"
        case .ok: return "ok"
        case .error: return "error"
        }
    }
}

public struct SpanStatistics: Sendable {
    public let totalSpans: Int
    public let byCategory: [String: CategoryStatistics]
}

public struct CategoryStatistics: Sendable {
    public let count: Int
    public let meanDuration: TimeInterval
    public let p50Duration: TimeInterval
    public let p95Duration: TimeInterval
    public let p99Duration: TimeInterval
    public let minDuration: TimeInterval
    public let maxDuration: TimeInterval
}
