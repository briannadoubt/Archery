import Foundation
import os.log

// MARK: - Console Exporter

public actor ConsoleExporter: TelemetryExporter {
    private let logger = Logger(subsystem: "Archery", category: "ConsoleExporter")
    private let prettyPrint: Bool
    
    public init(prettyPrint: Bool = true) {
        self.prettyPrint = prettyPrint
    }
    
    public func export(spans: [Span]) async throws {
        for span in spans {
            let duration = span.duration.map { String(format: "%.3fms", $0 * 1000) } ?? "ongoing"
            let attributes = formatAttributes(span.attributes)
            
            logger.info("""
                [SPAN] \(span.name)
                  TraceID: \(span.context.traceId)
                  SpanID: \(span.context.spanId)
                  Duration: \(duration)
                  Status: \(String(describing: span.status))
                  \(attributes)
                """)
            
            for event in span.events {
                logger.debug("  [EVENT] \(event.name) at \(event.timestamp)")
            }
        }
    }
    
    public func export(metrics: [any Metric]) async throws {
        for metric in metrics {
            let unit = metric.unit?.rawValue ?? ""
            let attributes = formatAttributes(metric.attributes)
            
            logger.info("""
                [METRIC] \(metric.name): \(metric.value) \(unit)
                  TraceID: \(metric.context.traceId)
                  \(attributes)
                """)
        }
    }
    
    public func export(logs: [LogEntry]) async throws {
        for log in logs {
            let level = log.level.rawValue.uppercased()
            let attributes = log.attributes.map { "  \($0.key): \($0.value)" }.joined(separator: "\n")
            
            logger.log(level: logLevel(for: log.level), """
                [\(level)] \(log.message)
                  TraceID: \(log.context.traceId)
                  SpanID: \(log.context.spanId)
                  \(attributes)
                """)
            
            if let exception = log.exception {
                logger.error("""
                    [EXCEPTION] \(exception.type): \(exception.message)
                    \(exception.stackTrace.joined(separator: "\n"))
                    """)
            }
        }
    }
    
    public func flush() async throws {
        // Console exporter doesn't buffer
    }
    
    public func shutdown() async throws {
        // No cleanup needed
    }
    
    private func formatAttributes(_ attributes: [String: Any]) -> String {
        guard !attributes.isEmpty else { return "" }
        
        if prettyPrint {
            return attributes
                .map { "  \($0.key): \($0.value)" }
                .joined(separator: "\n")
        } else {
            return attributes
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
        }
    }
    
    private func logLevel(for level: LogEntry.Level) -> OSLogType {
        switch level {
        case .trace, .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .default
        case .error:
            return .error
        case .critical:
            return .fault
        }
    }
}

// MARK: - OpenTelemetry Exporter

public actor OpenTelemetryExporter: TelemetryExporter {
    private let endpoint: URL
    private let headers: [String: String]
    private let session: URLSession
    private let batchSize: Int
    private let flushInterval: TimeInterval
    
    private var pendingSpans: [Span] = []
    private var pendingMetrics: [any Metric] = []
    private var pendingLogs: [LogEntry] = []
    private var flushTask: Task<Void, Never>?
    
    public init(
        endpoint: URL,
        headers: [String: String] = [:],
        batchSize: Int = 100,
        flushInterval: TimeInterval = 10
    ) {
        self.endpoint = endpoint
        self.headers = headers
        self.batchSize = batchSize
        self.flushInterval = flushInterval
        
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = headers
        self.session = URLSession(configuration: config)
    }
    
    deinit {
        flushTask?.cancel()
    }
    
    func initialize() {
        startFlushTimer()
    }
    
    private func startFlushTimer() {
        flushTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(flushInterval * 1_000_000_000))
                try? await flush()
            }
        }
    }
    
    public func export(spans: [Span]) async throws {
        pendingSpans.append(contentsOf: spans)
        if pendingSpans.count >= batchSize {
            try await flushSpans()
        }
    }
    
    public func export(metrics: [any Metric]) async throws {
        pendingMetrics.append(contentsOf: metrics)
        if pendingMetrics.count >= batchSize {
            try await flushMetrics()
        }
    }
    
    public func export(logs: [LogEntry]) async throws {
        pendingLogs.append(contentsOf: logs)
        if pendingLogs.count >= batchSize {
            try await flushLogs()
        }
    }
    
    public func flush() async throws {
        try await flushSpans()
        try await flushMetrics()
        try await flushLogs()
    }
    
    public func shutdown() async throws {
        flushTask?.cancel()
        try await flush()
    }
    
    private func flushSpans() async throws {
        guard !pendingSpans.isEmpty else { return }
        
        let spans = pendingSpans
        pendingSpans.removeAll()
        
        let payload = OTelSpanPayload(resourceSpans: [
            ResourceSpans(
                resource: Resource(attributes: resourceAttributes()),
                scopeSpans: [
                    ScopeSpans(
                        scope: InstrumentationScope(name: "archery", version: "1.0.0"),
                        spans: spans.map { $0.toOTelSpan() }
                    )
                ]
            )
        ])
        
        let url = endpoint.appendingPathComponent("v1/traces")
        try await send(payload, to: url)
    }
    
    private func flushMetrics() async throws {
        guard !pendingMetrics.isEmpty else { return }
        
        let metrics = pendingMetrics
        pendingMetrics.removeAll()
        
        let payload = OTelMetricPayload(resourceMetrics: [
            ResourceMetrics(
                resource: Resource(attributes: resourceAttributes()),
                scopeMetrics: [
                    ScopeMetrics(
                        scope: InstrumentationScope(name: "archery", version: "1.0.0"),
                        metrics: metrics.map { $0.toOTelMetric() }
                    )
                ]
            )
        ])
        
        let url = endpoint.appendingPathComponent("v1/metrics")
        try await send(payload, to: url)
    }
    
    private func flushLogs() async throws {
        guard !pendingLogs.isEmpty else { return }
        
        let logs = pendingLogs
        pendingLogs.removeAll()
        
        let payload = OTelLogPayload(resourceLogs: [
            ResourceLogs(
                resource: Resource(attributes: resourceAttributes()),
                scopeLogs: [
                    ScopeLogs(
                        scope: InstrumentationScope(name: "archery", version: "1.0.0"),
                        logs: logs.map { $0.toOTelLog() }
                    )
                ]
            )
        ])
        
        let url = endpoint.appendingPathComponent("v1/logs")
        try await send(payload, to: url)
    }
    
    private func send<T: Encodable>(_ payload: T, to url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TelemetryError.exportFailed
        }
    }
    
    private func resourceAttributes() -> [OTelAttribute] {
        let info = AppInfo.current
        let device = DeviceInfo.current
        
        return [
            OTelAttribute(key: "service.name", value: .string(info.name)),
            OTelAttribute(key: "service.version", value: .string(info.version)),
            OTelAttribute(key: "device.model", value: .string(device.model)),
            OTelAttribute(key: "os.type", value: .string(device.platform)),
            OTelAttribute(key: "os.version", value: .string(device.osVersion))
        ]
    }
}

// MARK: - File Exporter

public actor FileExporter: TelemetryExporter {
    private let directory: URL
    private let maxFileSize: Int
    private let maxFiles: Int
    private var currentFile: URL?
    private var fileHandle: FileHandle?
    
    public init(directory: URL, maxFileSize: Int = 10_485_760, maxFiles: Int = 10) {
        self.directory = directory
        self.maxFileSize = maxFileSize
        self.maxFiles = maxFiles
    }
    
    public func export(spans: [Span]) async throws {
        for span in spans {
            let json = span.toExportable()
            if let data = try? JSONSerialization.data(withJSONObject: json) {
                try await write(data)
            }
        }
    }
    
    public func export(metrics: [any Metric]) async throws {
        for metric in metrics {
            let json = metric.toExportable()
            if let data = try? JSONSerialization.data(withJSONObject: json) {
                try await write(data)
            }
        }
    }
    
    public func export(logs: [LogEntry]) async throws {
        for log in logs {
            let json = log.toExportable()
            if let data = try? JSONSerialization.data(withJSONObject: json) {
                try await write(data)
            }
        }
    }
    
    public func flush() async throws {
        fileHandle?.synchronizeFile()
    }
    
    public func shutdown() async throws {
        try await flush()
        try? fileHandle?.close()
        fileHandle = nil
    }
    
    private func write(_ data: Data) async throws {
        if fileHandle == nil {
            try await createNewFile()
        }
        
        if let handle = fileHandle {
            let currentSize = try handle.seekToEnd()
            if Int(currentSize) + data.count > maxFileSize {
                try handle.close()
                try await createNewFile()
            }
        }
        
        fileHandle?.write(data)
        fileHandle?.write("\n".data(using: .utf8)!)
    }
    
    private func createNewFile() async throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = "telemetry_\(timestamp).jsonl"
        currentFile = directory.appendingPathComponent(filename)
        
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        FileManager.default.createFile(atPath: currentFile!.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: currentFile!)
        
        // Clean up old files
        try await cleanupOldFiles()
    }
    
    private func cleanupOldFiles() async throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.lastPathComponent.hasPrefix("telemetry_") }
            .sorted { url1, url2 in
                let date1 = try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                let date2 = try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                return date1! > date2!
            }
        
        if files.count > maxFiles {
            for file in files[maxFiles...] {
                try FileManager.default.removeItem(at: file)
            }
        }
    }
}

// MARK: - Batch Exporter

public actor BatchExporter: TelemetryExporter {
    private let wrapped: any TelemetryExporter
    private let batchSize: Int
    private let flushInterval: TimeInterval
    
    private var pendingSpans: [Span] = []
    private var pendingMetrics: [any Metric] = []
    private var pendingLogs: [LogEntry] = []
    private var flushTask: Task<Void, Never>?
    
    public init(
        wrapped: any TelemetryExporter,
        batchSize: Int = 100,
        flushInterval: TimeInterval = 10
    ) {
        self.wrapped = wrapped
        self.batchSize = batchSize
        self.flushInterval = flushInterval
    }
    
    deinit {
        flushTask?.cancel()
    }
    
    func initialize() {
        startFlushTimer()
    }
    
    private func startFlushTimer() {
        flushTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(flushInterval * 1_000_000_000))
                try? await flush()
            }
        }
    }
    
    public func export(spans: [Span]) async throws {
        pendingSpans.append(contentsOf: spans)
        if pendingSpans.count >= batchSize {
            let batch = pendingSpans
            pendingSpans.removeAll()
            try await wrapped.export(spans: batch)
        }
    }
    
    public func export(metrics: [any Metric]) async throws {
        pendingMetrics.append(contentsOf: metrics)
        if pendingMetrics.count >= batchSize {
            let batch = pendingMetrics
            pendingMetrics.removeAll()
            try await wrapped.export(metrics: batch)
        }
    }
    
    public func export(logs: [LogEntry]) async throws {
        pendingLogs.append(contentsOf: logs)
        if pendingLogs.count >= batchSize {
            let batch = pendingLogs
            pendingLogs.removeAll()
            try await wrapped.export(logs: batch)
        }
    }
    
    public func flush() async throws {
        if !pendingSpans.isEmpty {
            let batch = pendingSpans
            pendingSpans.removeAll()
            try await wrapped.export(spans: batch)
        }
        
        if !pendingMetrics.isEmpty {
            let batch = pendingMetrics
            pendingMetrics.removeAll()
            try await wrapped.export(metrics: batch)
        }
        
        if !pendingLogs.isEmpty {
            let batch = pendingLogs
            pendingLogs.removeAll()
            try await wrapped.export(logs: batch)
        }
        
        try await wrapped.flush()
    }
    
    public func shutdown() async throws {
        flushTask?.cancel()
        try await flush()
        try await wrapped.shutdown()
    }
}

// MARK: - Error Types

public enum TelemetryError: Error {
    case exportFailed
    case invalidConfiguration
    case quotaExceeded
}

// MARK: - OpenTelemetry Data Structures

private struct OTelSpanPayload: Codable {
    let resourceSpans: [ResourceSpans]
}

private struct OTelMetricPayload: Codable {
    let resourceMetrics: [ResourceMetrics]
}

private struct OTelLogPayload: Codable {
    let resourceLogs: [ResourceLogs]
}

private struct ResourceSpans: Codable {
    let resource: Resource
    let scopeSpans: [ScopeSpans]
}

private struct ResourceMetrics: Codable {
    let resource: Resource
    let scopeMetrics: [ScopeMetrics]
}

private struct ResourceLogs: Codable {
    let resource: Resource
    let scopeLogs: [ScopeLogs]
}

private struct Resource: Codable {
    let attributes: [OTelAttribute]
}

private struct InstrumentationScope: Codable {
    let name: String
    let version: String
}

private struct ScopeSpans: Codable {
    let scope: InstrumentationScope
    let spans: [OTelSpan]
}

private struct ScopeMetrics: Codable {
    let scope: InstrumentationScope
    let metrics: [OTelMetric]
}

private struct ScopeLogs: Codable {
    let scope: InstrumentationScope
    let logs: [OTelLog]
}

private struct OTelSpan: Codable {
    let traceId: String
    let spanId: String
    let parentSpanId: String?
    let name: String
    let startTimeUnixNano: UInt64
    let endTimeUnixNano: UInt64?
    let attributes: [OTelAttribute]
}

private struct OTelMetric: Codable {
    let name: String
    let unit: String?
    let gauge: OTelGauge?
    let sum: OTelSum?
    let histogram: OTelHistogram?
}

private struct OTelLog: Codable {
    let timeUnixNano: UInt64
    let severityNumber: Int
    let severityText: String
    let body: OTelValue
    let attributes: [OTelAttribute]
    let traceId: String
    let spanId: String
}

private struct OTelGauge: Codable {
    let dataPoints: [OTelNumberDataPoint]
}

private struct OTelSum: Codable {
    let dataPoints: [OTelNumberDataPoint]
}

private struct OTelHistogram: Codable {
    let dataPoints: [OTelHistogramDataPoint]
}

private struct OTelNumberDataPoint: Codable {
    let timeUnixNano: UInt64
    let value: Double
    let attributes: [OTelAttribute]
}

private struct OTelHistogramDataPoint: Codable {
    let timeUnixNano: UInt64
    let count: UInt64
    let sum: Double
    let bucketCounts: [UInt64]
    let explicitBounds: [Double]
    let attributes: [OTelAttribute]
}

private struct OTelAttribute: Codable {
    let key: String
    let value: OTelValue
}

private enum OTelValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([OTelValue])
    case kvlist([OTelAttribute])
}

// MARK: - Export Extensions

private extension Span {
    func toOTelSpan() -> OTelSpan {
        OTelSpan(
            traceId: context.traceId,
            spanId: context.spanId,
            parentSpanId: context.parentSpanId,
            name: name,
            startTimeUnixNano: UInt64(startTime.timeIntervalSince1970 * 1_000_000_000),
            endTimeUnixNano: endTime.map { UInt64($0.timeIntervalSince1970 * 1_000_000_000) },
            attributes: attributes.map { OTelAttribute(key: $0.key, value: .string($0.value)) }
        )
    }
    
    func toExportable() -> [String: Any] {
        [
            "type": "span",
            "traceId": context.traceId,
            "spanId": context.spanId,
            "parentSpanId": context.parentSpanId as Any,
            "name": name,
            "startTime": startTime.timeIntervalSince1970,
            "endTime": endTime?.timeIntervalSince1970 as Any,
            "duration": duration as Any,
            "attributes": attributes,
            "events": events.map { ["name": $0.name, "timestamp": $0.timestamp.timeIntervalSince1970, "attributes": $0.attributes] },
            "status": String(describing: status)
        ]
    }
}

private extension Metric {
    func toOTelMetric() -> OTelMetric {
        let dataPoint = OTelNumberDataPoint(
            timeUnixNano: UInt64(timestamp.timeIntervalSince1970 * 1_000_000_000),
            value: value,
            attributes: attributes.map { OTelAttribute(key: $0.key, value: .string($0.value)) }
        )
        
        return OTelMetric(
            name: name,
            unit: unit?.rawValue,
            gauge: self is Gauge ? OTelGauge(dataPoints: [dataPoint]) : nil,
            sum: self is Counter ? OTelSum(dataPoints: [dataPoint]) : nil,
            histogram: nil
        )
    }
    
    func toExportable() -> [String: Any] {
        [
            "type": "metric",
            "name": name,
            "value": value,
            "unit": unit?.rawValue as Any,
            "timestamp": timestamp.timeIntervalSince1970,
            "traceId": context.traceId,
            "attributes": attributes
        ]
    }
}

private extension LogEntry {
    func toOTelLog() -> OTelLog {
        OTelLog(
            timeUnixNano: UInt64(timestamp.timeIntervalSince1970 * 1_000_000_000),
            severityNumber: severityNumber,
            severityText: level.rawValue.uppercased(),
            body: .string(message),
            attributes: attributes.map { OTelAttribute(key: $0.key, value: .string($0.value)) },
            traceId: context.traceId,
            spanId: context.spanId
        )
    }
    
    var severityNumber: Int {
        switch level {
        case .trace: return 1
        case .debug: return 5
        case .info: return 9
        case .warning: return 13
        case .error: return 17
        case .critical: return 21
        }
    }
    
    func toExportable() -> [String: Any] {
        [
            "type": "log",
            "timestamp": timestamp.timeIntervalSince1970,
            "level": level.rawValue,
            "message": message,
            "traceId": context.traceId,
            "spanId": context.spanId,
            "attributes": attributes,
            "exception": exception.map { ["type": $0.type, "message": $0.message, "stackTrace": $0.stackTrace] } as Any
        ]
    }
}