import Foundation
import os.log

// MARK: - Correlation Context

public struct CorrelationContext: Sendable {
    public let traceId: String
    public let spanId: String
    public let parentSpanId: String?
    public let baggage: [String: String]
    public let sampled: Bool
    
    public init(
        traceId: String? = nil,
        spanId: String? = nil,
        parentSpanId: String? = nil,
        baggage: [String: String] = [:],
        sampled: Bool = true
    ) {
        self.traceId = traceId ?? Self.generateTraceId()
        self.spanId = spanId ?? Self.generateSpanId()
        self.parentSpanId = parentSpanId
        self.baggage = baggage
        self.sampled = sampled
    }
    
    public static func generateTraceId() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
    
    public static func generateSpanId() -> String {
        String(format: "%016x", UInt64.random(in: 0...UInt64.max))
    }
    
    public func createChildContext() -> CorrelationContext {
        CorrelationContext(
            traceId: traceId,
            spanId: Self.generateSpanId(),
            parentSpanId: spanId,
            baggage: baggage,
            sampled: sampled
        )
    }
    
    public func withBaggage(_ key: String, value: String) -> CorrelationContext {
        var newBaggage = baggage
        newBaggage[key] = value
        return CorrelationContext(
            traceId: traceId,
            spanId: spanId,
            parentSpanId: parentSpanId,
            baggage: newBaggage,
            sampled: sampled
        )
    }
}

// MARK: - Context Propagation

@MainActor
@Observable
public final class ContextPropagator {
    public static let shared = ContextPropagator()

    public private(set) var currentContext: CorrelationContext
    private var contextStack: [CorrelationContext] = []
    
    private init() {
        self.currentContext = CorrelationContext()
    }
    
    public func startTrace(sampled: Bool = true) -> CorrelationContext {
        let context = CorrelationContext(sampled: sampled)
        currentContext = context
        return context
    }
    
    public func startSpan(name: String, attributes: [String: String] = [:]) -> Span {
        let childContext = currentContext.createChildContext()
        contextStack.append(currentContext)
        currentContext = childContext
        
        return Span(
            name: name,
            context: childContext,
            attributes: attributes,
            startTime: Date()
        )
    }
    
    public func endSpan(_ span: Span) {
        span.end()
        
        if !contextStack.isEmpty {
            currentContext = contextStack.removeLast()
        }
    }
    
    public func withContext<T>(_ context: CorrelationContext, operation: () throws -> T) rethrows -> T {
        let previousContext = currentContext
        currentContext = context
        defer { currentContext = previousContext }
        return try operation()
    }
    
    public func injectIntoHeaders(_ headers: inout [String: String]) {
        headers["X-Trace-Id"] = currentContext.traceId
        headers["X-Span-Id"] = currentContext.spanId
        if let parentSpanId = currentContext.parentSpanId {
            headers["X-Parent-Span-Id"] = parentSpanId
        }
        headers["X-Sampled"] = currentContext.sampled ? "1" : "0"
        
        for (key, value) in currentContext.baggage {
            headers["X-Baggage-\(key)"] = value
        }
    }
    
    public func extractFromHeaders(_ headers: [String: String]) -> CorrelationContext {
        let traceId = headers["X-Trace-Id"]
        let spanId = headers["X-Span-Id"]
        let parentSpanId = headers["X-Parent-Span-Id"]
        let sampled = headers["X-Sampled"] == "1"
        
        var baggage: [String: String] = [:]
        for (key, value) in headers where key.hasPrefix("X-Baggage-") {
            let baggageKey = String(key.dropFirst("X-Baggage-".count))
            baggage[baggageKey] = value
        }
        
        return CorrelationContext(
            traceId: traceId,
            spanId: spanId,
            parentSpanId: parentSpanId,
            baggage: baggage,
            sampled: sampled
        )
    }
}

// MARK: - Span

public final class Span: @unchecked Sendable {
    public let name: String
    public let context: CorrelationContext
    public let startTime: Date
    public private(set) var endTime: Date?
    public private(set) var attributes: [String: String]
    public private(set) var events: [SpanEvent] = []
    public private(set) var status: SpanStatus = .unset
    
    private let lock = NSLock()
    
    public init(
        name: String,
        context: CorrelationContext,
        attributes: [String: String] = [:],
        startTime: Date = Date()
    ) {
        self.name = name
        self.context = context
        self.attributes = attributes
        self.startTime = startTime
    }
    
    public func setAttribute(_ key: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        attributes[key] = value
    }
    
    public func addEvent(_ name: String, attributes: [String: String] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        events.append(SpanEvent(
            name: name,
            timestamp: Date(),
            attributes: attributes
        ))
    }
    
    public func setStatus(_ status: SpanStatus, message: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        self.status = status
        if let message = message {
            attributes["status.message"] = message
        }
    }
    
    public func end(at time: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }

        guard endTime == nil else { return }
        endTime = time

        Task {
            await ObservabilityEngine.shared.recordSpan(self)
        }
    }
    
    public var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
}

public struct SpanEvent {
    public let name: String
    public let timestamp: Date
    public let attributes: [String: String]
}

public enum SpanStatus: Equatable {
    case unset
    case ok
    case error(Error?)

    public static func == (lhs: SpanStatus, rhs: SpanStatus) -> Bool {
        switch (lhs, rhs) {
        case (.unset, .unset), (.ok, .ok):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            // Compare by presence of error, not by specific error
            return (lhsError == nil) == (rhsError == nil)
        default:
            return false
        }
    }
}

// MARK: - Breadcrumb System

public struct Breadcrumb: Sendable, Identifiable {
    public let id = UUID()
    public enum Category: String, Sendable {
        case navigation
        case ui
        case network
        case database
        case custom
        case error
        case debug
        case user
    }
    
    public let timestamp: Date
    public let category: Category
    public let message: String
    public let level: BreadcrumbLevel
    public let data: [String: String]
    public let context: CorrelationContext
    
    public init(
        category: Category,
        message: String,
        level: BreadcrumbLevel = .info,
        data: [String: String] = [:],
        context: CorrelationContext? = nil
    ) {
        self.timestamp = Date()
        self.category = category
        self.message = message
        self.level = level
        self.data = data
        self.context = context ?? CorrelationContext()
    }

    @MainActor
    public init(
        category: Category,
        message: String,
        level: BreadcrumbLevel = .info,
        data: [String: String] = [:],
        useCurrentContext: Bool
    ) {
        self.timestamp = Date()
        self.category = category
        self.message = message
        self.level = level
        self.data = data
        self.context = useCurrentContext ? ContextPropagator.shared.currentContext : CorrelationContext()
    }
}

public enum BreadcrumbLevel: String, Sendable {
    case debug
    case info
    case warning
    case error
    case critical
}

public actor BreadcrumbRecorder {
    public static let shared = BreadcrumbRecorder()

    private var breadcrumbs: [Breadcrumb] = []
    private let maxBreadcrumbs: Int
    private var hooks: [(Breadcrumb) -> Void] = []

    public init(maxBreadcrumbs: Int = 100) {
        self.maxBreadcrumbs = maxBreadcrumbs
    }
    
    public func record(_ breadcrumb: Breadcrumb) {
        breadcrumbs.append(breadcrumb)
        
        if breadcrumbs.count > maxBreadcrumbs {
            breadcrumbs.removeFirst(breadcrumbs.count - maxBreadcrumbs)
        }
        
        for hook in hooks {
            hook(breadcrumb)
        }
    }
    
    public func record(
        category: Breadcrumb.Category,
        message: String,
        level: BreadcrumbLevel = .info,
        data: [String: String] = [:]
    ) {
        let breadcrumb = Breadcrumb(
            category: category,
            message: message,
            level: level,
            data: data
        )
        record(breadcrumb)
    }
    
    public func getBreadcrumbs(limit: Int? = nil) -> [Breadcrumb] {
        if let limit = limit {
            return Array(breadcrumbs.suffix(limit))
        }
        return breadcrumbs
    }
    
    public func clear() {
        breadcrumbs.removeAll()
    }
    
    public func addHook(_ hook: @escaping (Breadcrumb) -> Void) {
        hooks.append(hook)
    }
}

// MARK: - Observability Engine

public actor ObservabilityEngine {
    public static let shared = ObservabilityEngine()

    private var exporters: [any TelemetryExporter] = []
    private var samplers: [any TelemetrySampler] = []
    private var enrichers: [any TelemetryEnricher] = []

    private init() {
        #if DEBUG
        exporters.append(ConsoleExporter())
        #endif
    }
    
    public func addExporter(_ exporter: any TelemetryExporter) {
        exporters.append(exporter)
    }
    
    public func addSampler(_ sampler: any TelemetrySampler) {
        samplers.append(sampler)
    }
    
    public func addEnricher(_ enricher: any TelemetryEnricher) {
        enrichers.append(enricher)
    }
    
    public func recordSpan(_ span: Span) {
        guard shouldSample(span) else { return }
        
        let enrichedSpan = enrich(span)
        
        for exporter in exporters {
            Task {
                try? await exporter.export(spans: [enrichedSpan])
            }
        }
    }
    
    public func recordMetric(_ metric: any Metric) {
        guard shouldSampleMetric(metric) else { return }
        
        for exporter in exporters {
            Task {
                try? await exporter.export(metrics: [metric])
            }
        }
    }
    
    public func recordLog(_ log: LogEntry) {
        guard shouldSampleLog(log) else { return }
        
        for exporter in exporters {
            Task {
                try? await exporter.export(logs: [log])
            }
        }
    }
    
    private func shouldSample(_ span: Span) -> Bool {
        guard span.context.sampled else { return false }
        
        for sampler in samplers {
            if !sampler.shouldSample(span: span) {
                return false
            }
        }
        return true
    }
    
    private func shouldSampleMetric(_ metric: any Metric) -> Bool {
        for sampler in samplers {
            if !sampler.shouldSampleMetric(metric: metric) {
                return false
            }
        }
        return true
    }
    
    private func shouldSampleLog(_ log: LogEntry) -> Bool {
        for sampler in samplers {
            if !sampler.shouldSampleLog(log: log) {
                return false
            }
        }
        return true
    }
    
    private func enrich(_ span: Span) -> Span {
        var enrichedSpan = span
        
        for enricher in enrichers {
            enricher.enrich(span: &enrichedSpan)
        }
        
        return enrichedSpan
    }
    
    public func flush() async {
        await withTaskGroup(of: Void.self) { group in
            for exporter in exporters {
                group.addTask {
                    try? await exporter.flush()
                }
            }
        }
    }
    
    public func shutdown() async {
        await flush()
        exporters.removeAll()
        samplers.removeAll()
        enrichers.removeAll()
    }
}