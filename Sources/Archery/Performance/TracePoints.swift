import Foundation
import os.signpost
import os.log

// MARK: - Performance Tracing

public final class PerformanceTracer {
    public static let shared = PerformanceTracer()
    
    private let signposter = OSSignposter()
    private let log = OSLog(subsystem: "com.archery.performance", category: "tracing")
    private var activeIntervals: [String: OSSignpostIntervalState] = [:]
    private var isEnabled: Bool
    
    private init() {
        #if DEBUG
        self.isEnabled = ProcessInfo.processInfo.environment["ENABLE_TRACING"] == "1"
        #else
        self.isEnabled = false
        #endif
    }
    
    public func configure(enabled: Bool) {
        self.isEnabled = enabled
    }
    
    // MARK: - Signpost APIs
    
    @discardableResult
    public func beginInterval(
        _ name: StaticString,
        id: OSSignpostID = .exclusive,
        metadata: [String: Any]? = nil
    ) -> OSSignpostIntervalState? {
        guard isEnabled else { return nil }
        
        let state = signposter.beginInterval(name, id: id, "\(metadata ?? [:])")
        activeIntervals[String(name)] = state
        return state
    }
    
    public func endInterval(
        _ name: StaticString,
        state: OSSignpostIntervalState? = nil
    ) {
        guard isEnabled else { return }
        
        if let state = state ?? activeIntervals[String(name)] {
            signposter.endInterval(name, state)
            activeIntervals[String(name)] = nil
        }
    }
    
    public func emitEvent(
        _ name: StaticString,
        id: OSSignpostID = .exclusive,
        metadata: [String: Any]? = nil
    ) {
        guard isEnabled else { return }
        signposter.emitEvent(name, id: id, "\(metadata ?? [:])")
    }
    
    // MARK: - Structured Trace Points
    
    public func traceViewBody<T>(
        _ viewName: String,
        body: () throws -> T
    ) rethrows -> T {
        let state = beginInterval("View.body", metadata: ["view": viewName])
        defer { endInterval("View.body", state: state) }
        return try body()
    }
    
    public func traceViewModelLoad<T>(
        _ vmName: String,
        body: () async throws -> T
    ) async rethrows -> T {
        let state = beginInterval("ViewModel.load", metadata: ["viewModel": vmName])
        defer { endInterval("ViewModel.load", state: state) }
        return try await body()
    }
    
    public func traceRepositoryFetch<T>(
        _ repoName: String,
        endpoint: String,
        body: () async throws -> T
    ) async rethrows -> T {
        let state = beginInterval("Repository.fetch", metadata: [
            "repository": repoName,
            "endpoint": endpoint
        ])
        defer { endInterval("Repository.fetch", state: state) }
        return try await body()
    }
    
    public func traceNavigation(
        from: String,
        to: String,
        trigger: NavigationTrigger
    ) {
        emitEvent("Navigation", metadata: [
            "from": from,
            "to": to,
            "trigger": trigger.rawValue
        ])
    }
    
    public enum NavigationTrigger: String {
        case tap = "tap"
        case swipe = "swipe"
        case deepLink = "deepLink"
        case programmatic = "programmatic"
    }
}

// MARK: - Performance Markers

public struct PerformanceMarker {
    public let name: String
    public let timestamp: CFAbsoluteTime
    public let metadata: [String: Any]
    
    public init(name: String, metadata: [String: Any] = [:]) {
        self.name = name
        self.timestamp = CFAbsoluteTimeGetCurrent()
        self.metadata = metadata
    }
}

// MARK: - Trace Context

public final class TraceContext {
    public let traceId: String
    public let spanId: String
    public let parentSpanId: String?
    public var metadata: [String: Any] = [:]
    private var markers: [PerformanceMarker] = []
    private let startTime: CFAbsoluteTime
    
    public init(
        traceId: String? = nil,
        parentSpanId: String? = nil
    ) {
        self.traceId = traceId ?? UUID().uuidString
        self.spanId = UUID().uuidString
        self.parentSpanId = parentSpanId
        self.startTime = CFAbsoluteTimeGetCurrent()
    }
    
    public func addMarker(_ marker: PerformanceMarker) {
        markers.append(marker)
    }
    
    public func addMarker(name: String, metadata: [String: Any] = [:]) {
        markers.append(PerformanceMarker(name: name, metadata: metadata))
    }
    
    public var duration: TimeInterval {
        CFAbsoluteTimeGetCurrent() - startTime
    }
    
    public func export() -> TraceExport {
        TraceExport(
            traceId: traceId,
            spanId: spanId,
            parentSpanId: parentSpanId,
            startTime: startTime,
            duration: duration,
            markers: markers,
            metadata: metadata
        )
    }
}

public struct TraceExport: Codable {
    public let traceId: String
    public let spanId: String
    public let parentSpanId: String?
    public let startTime: CFAbsoluteTime
    public let duration: TimeInterval
    public let markers: [MarkerExport]
    public let metadata: [String: String]
    
    public struct MarkerExport: Codable {
        public let name: String
        public let timestamp: CFAbsoluteTime
        public let metadata: [String: String]
    }
    
    init(
        traceId: String,
        spanId: String,
        parentSpanId: String?,
        startTime: CFAbsoluteTime,
        duration: TimeInterval,
        markers: [PerformanceMarker],
        metadata: [String: Any]
    ) {
        self.traceId = traceId
        self.spanId = spanId
        self.parentSpanId = parentSpanId
        self.startTime = startTime
        self.duration = duration
        self.markers = markers.map { marker in
            MarkerExport(
                name: marker.name,
                timestamp: marker.timestamp,
                metadata: marker.metadata.compactMapValues { "\($0)" }
            )
        }
        self.metadata = metadata.compactMapValues { "\($0)" }
    }
}

// MARK: - Trace Aggregator

public final class TraceAggregator {
    private var traces: [TraceExport] = []
    private let maxTraces: Int
    private let queue = DispatchQueue(label: "com.archery.traces", attributes: .concurrent)
    
    public init(maxTraces: Int = 1000) {
        self.maxTraces = maxTraces
    }
    
    public func record(_ trace: TraceExport) {
        queue.async(flags: .barrier) {
            self.traces.append(trace)
            if self.traces.count > self.maxTraces {
                self.traces.removeFirst(self.traces.count - self.maxTraces)
            }
        }
    }
    
    public func getTraces() -> [TraceExport] {
        queue.sync { traces }
    }
    
    public func clear() {
        queue.async(flags: .barrier) {
            self.traces.removeAll()
        }
    }
    
    public func exportToInstruments(url: URL) throws {
        let traces = getTraces()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(traces)
        try data.write(to: url)
    }
}