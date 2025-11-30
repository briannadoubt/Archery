import Foundation

// MARK: - Core Protocols

public protocol TelemetryExporter: Sendable {
    func export(spans: [Span]) async throws
    func export(metrics: [any Metric]) async throws
    func export(logs: [LogEntry]) async throws
    func flush() async throws
    func shutdown() async throws
}

public protocol TelemetrySampler: Sendable {
    func shouldSample(span: Span) -> Bool
    func shouldSampleMetric(metric: any Metric) -> Bool
    func shouldSampleLog(log: LogEntry) -> Bool
}

public protocol TelemetryEnricher: Sendable {
    func enrich(span: inout Span)
    func enrich(metric: inout any Metric)
    func enrich(log: inout LogEntry)
}

// MARK: - Metric Types

public protocol Metric: Sendable {
    var name: String { get }
    var value: Double { get }
    var unit: MetricUnit? { get }
    var timestamp: Date { get }
    var attributes: [String: String] { get }
    var context: CorrelationContext { get }
}

public enum MetricUnit: String, Sendable {
    case bytes
    case milliseconds
    case seconds
    case percent
    case count
    case custom
}

public struct Counter: Metric {
    public let name: String
    public let value: Double
    public let unit: MetricUnit?
    public let timestamp: Date
    public let attributes: [String: String]
    public let context: CorrelationContext
    
    public init(
        name: String,
        value: Double = 1,
        unit: MetricUnit? = .count,
        attributes: [String: String] = [:],
        context: CorrelationContext? = nil
    ) {
        self.name = name
        self.value = value
        self.unit = unit
        self.timestamp = Date()
        self.attributes = attributes
        if let context = context {
            self.context = context
        } else {
            // Create a default context without accessing MainActor
            self.context = CorrelationContext()
        }
    }
}

public struct Gauge: Metric {
    public let name: String
    public let value: Double
    public let unit: MetricUnit?
    public let timestamp: Date
    public let attributes: [String: String]
    public let context: CorrelationContext
    
    public init(
        name: String,
        value: Double,
        unit: MetricUnit? = nil,
        attributes: [String: String] = [:],
        context: CorrelationContext? = nil
    ) {
        self.name = name
        self.value = value
        self.unit = unit
        self.timestamp = Date()
        self.attributes = attributes
        if let context = context {
            self.context = context
        } else {
            // Create a default context without accessing MainActor
            self.context = CorrelationContext()
        }
    }
}

public struct Histogram: Metric {
    public let name: String
    public let value: Double
    public let unit: MetricUnit?
    public let timestamp: Date
    public let attributes: [String: String]
    public let context: CorrelationContext
    public let buckets: [Double]
    
    public init(
        name: String,
        value: Double,
        unit: MetricUnit? = nil,
        buckets: [Double] = [0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1, 2.5, 5, 7.5, 10],
        attributes: [String: String] = [:],
        context: CorrelationContext? = nil
    ) {
        self.name = name
        self.value = value
        self.unit = unit
        self.timestamp = Date()
        self.buckets = buckets
        self.attributes = attributes
        if let context = context {
            self.context = context
        } else {
            // Create a default context without accessing MainActor
            self.context = CorrelationContext()
        }
    }
}

// MARK: - Log Types

public struct LogEntry: Sendable {
    public enum Level: String, Sendable {
        case trace
        case debug
        case info
        case warning
        case error
        case critical
    }
    
    public let timestamp: Date
    public let level: Level
    public let message: String
    public let attributes: [String: String]
    public let context: CorrelationContext
    public let exception: ExceptionInfo?
    
    public init(
        level: Level,
        message: String,
        attributes: [String: String] = [:],
        context: CorrelationContext? = nil,
        exception: ExceptionInfo? = nil
    ) {
        self.timestamp = Date()
        self.level = level
        self.message = message
        self.attributes = attributes
        if let context = context {
            self.context = context
        } else {
            // Create a default context without accessing MainActor
            self.context = CorrelationContext()
        }
        self.exception = exception
    }
}

public struct ExceptionInfo: Sendable {
    public let type: String
    public let message: String
    public let stackTrace: [String]
    
    public init(type: String, message: String, stackTrace: [String]) {
        self.type = type
        self.message = message
        self.stackTrace = stackTrace
    }
}

// MARK: - Crash Reporting

public protocol CrashReporter: Sendable {
    func recordCrash(_ crash: CrashReport) async
    func recordException(_ exception: ExceptionInfo, context: CorrelationContext) async
    func addBreadcrumb(_ breadcrumb: Breadcrumb)
    func setUserInfo(_ info: [String: String])
    func clearUserInfo()
}

public struct CrashReport: Sendable {
    public let id: String
    public let timestamp: Date
    public let signal: String?
    public let exception: ExceptionInfo?
    public let threads: [ThreadInfo]
    public let breadcrumbs: [Breadcrumb]
    public let context: CorrelationContext
    public let device: DeviceInfo
    public let app: AppInfo
    
    public init(
        signal: String? = nil,
        exception: ExceptionInfo? = nil,
        threads: [ThreadInfo] = [],
        breadcrumbs: [Breadcrumb] = [],
        context: CorrelationContext? = nil,
        device: DeviceInfo? = nil,
        app: AppInfo? = nil
    ) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.signal = signal
        self.exception = exception
        self.threads = threads
        self.breadcrumbs = breadcrumbs
        if let context = context {
            self.context = context
        } else {
            // Create a default context without accessing MainActor
            self.context = CorrelationContext()
        }
        self.device = device ?? DeviceInfo.current
        self.app = app ?? AppInfo.current
    }
}

public struct ThreadInfo: Sendable {
    public let id: String
    public let name: String?
    public let crashed: Bool
    public let stackTrace: [StackFrame]
    
    public init(id: String, name: String? = nil, crashed: Bool = false, stackTrace: [StackFrame] = []) {
        self.id = id
        self.name = name
        self.crashed = crashed
        self.stackTrace = stackTrace
    }
}

public struct StackFrame: Sendable {
    public let address: String
    public let symbol: String?
    public let file: String?
    public let line: Int?
    public let column: Int?
    
    public init(address: String, symbol: String? = nil, file: String? = nil, line: Int? = nil, column: Int? = nil) {
        self.address = address
        self.symbol = symbol
        self.file = file
        self.line = line
        self.column = column
    }
}

public struct DeviceInfo: Sendable {
    public let model: String
    public let osVersion: String
    public let platform: String
    public let locale: String
    public let timezone: String
    
    public static var current: DeviceInfo {
        #if os(iOS) || os(tvOS)
        let platform = "iOS"
        #elseif os(macOS)
        let platform = "macOS"
        #elseif os(watchOS)
        let platform = "watchOS"
        #elseif os(visionOS)
        let platform = "visionOS"
        #else
        let platform = "Unknown"
        #endif
        
        return DeviceInfo(
            model: ProcessInfo.processInfo.hostName,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            platform: platform,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier
        )
    }
    
    public init(model: String, osVersion: String, platform: String, locale: String, timezone: String) {
        self.model = model
        self.osVersion = osVersion
        self.platform = platform
        self.locale = locale
        self.timezone = timezone
    }
}

public struct AppInfo: Sendable {
    public let name: String
    public let version: String
    public let build: String
    public let identifier: String
    
    public static var current: AppInfo {
        let bundle = Bundle.main
        return AppInfo(
            name: bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Unknown",
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            identifier: bundle.bundleIdentifier ?? "unknown"
        )
    }
    
    public init(name: String, version: String, build: String, identifier: String) {
        self.name = name
        self.version = version
        self.build = build
        self.identifier = identifier
    }
}