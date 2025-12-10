import Foundation
import os.signpost

// MARK: - Instruments Configuration

/// Configuration for Instruments profiling templates
public struct InstrumentsConfig {
    
    public let name: String
    public let templates: [InstrumentsTemplate]
    
    public init(name: String, @TemplateBuilder templates: () -> [InstrumentsTemplate]) {
        self.name = name
        self.templates = templates()
    }
    
    // MARK: - Export
    
    /// Export Instruments template configuration
    public func exportTemplate(to url: URL) throws {
        let plist = generatePlist()
        try plist.write(to: url)
    }
    
    private func generatePlist() -> Data {
        let dict: [String: Any] = [
            "$version": 100000,
            "$objects": templates.map { $0.toDictionary() },
            "$archiver": "NSKeyedArchiver",
            "$top": ["root": "$null"]
        ]
        
        return try! PropertyListSerialization.data(
            fromPropertyList: dict,
            format: .xml,
            options: 0
        )
    }
}

// MARK: - Instruments Template

public struct InstrumentsTemplate {
    public let type: TemplateType
    public let configuration: [String: Any]
    
    public init(type: TemplateType, configuration: [String: Any] = [:]) {
        self.type = type
        self.configuration = configuration
    }
    
    func toDictionary() -> [String: Any] {
        var dict = configuration
        dict["template_type"] = type.rawValue
        dict["template_name"] = type.displayName
        return dict
    }
}

public enum TemplateType: String {
    case timeProfiler = "com.apple.xray.instrument-type.coresampler2"
    case allocations = "com.apple.xray.instrument-type.alloc"
    case leaks = "com.apple.xray.instrument-type.leaks"
    case networkActivity = "com.apple.xray.instrument-type.network"
    case systemTrace = "com.apple.xray.instrument-type.system.trace"
    case metalSystemTrace = "com.apple.xray.instrument-type.metal-system-trace"
    case swiftUIProfiler = "com.apple.xray.instrument-type.swiftui"
    case hangDetection = "com.apple.xray.instrument-type.hangs"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .timeProfiler: return "Time Profiler"
        case .allocations: return "Allocations"
        case .leaks: return "Leaks"
        case .networkActivity: return "Network Activity"
        case .systemTrace: return "System Trace"
        case .metalSystemTrace: return "Metal System Trace"
        case .swiftUIProfiler: return "SwiftUI"
        case .hangDetection: return "Hang Detection"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Template Builder

@resultBuilder
public struct TemplateBuilder {
    public static func buildBlock(_ templates: InstrumentsTemplate...) -> [InstrumentsTemplate] {
        templates
    }
}

// MARK: - Signpost Integration

/// Signpost markers for Instruments integration
public struct SignpostMarkers {
    
    private static let log = OSLog(subsystem: "com.archery", category: .pointsOfInterest)
    
    // MARK: - App Lifecycle
    
    public static func appLaunch() -> SignpostInterval {
        SignpostInterval(log: log, name: "App Launch")
    }
    
    public static func sceneActivation() -> SignpostInterval {
        SignpostInterval(log: log, name: "Scene Activation")
    }
    
    // MARK: - View Lifecycle
    
    public static func viewAppear(view: String) -> SignpostInterval {
        SignpostInterval(log: log, name: "View Appear", metadata: ["view": view])
    }
    
    public static func viewRender(view: String) -> SignpostInterval {
        SignpostInterval(log: log, name: "View Render", metadata: ["view": view])
    }
    
    // MARK: - Data Operations
    
    public static func dataFetch(source: String) -> SignpostInterval {
        SignpostInterval(log: log, name: "Data Fetch", metadata: ["source": source])
    }
    
    public static func dataSave(destination: String) -> SignpostInterval {
        SignpostInterval(log: log, name: "Data Save", metadata: ["destination": destination])
    }
    
    // MARK: - Network Operations
    
    public static func networkRequest(url: String) -> SignpostInterval {
        SignpostInterval(log: log, name: "Network Request", metadata: ["url": url])
    }
    
    public static func imageLoad(url: String) -> SignpostInterval {
        SignpostInterval(log: log, name: "Image Load", metadata: ["url": url])
    }
    
    // MARK: - Custom Markers

    public static func custom(_ name: String, metadata: [String: String] = [:]) -> SignpostInterval {
        var allMetadata = metadata
        allMetadata["custom_name"] = name
        return SignpostInterval(log: log, name: "Custom", metadata: allMetadata)
    }
}

/// Signpost interval for measuring durations
public class SignpostInterval {
    private let log: OSLog
    private let name: StaticString
    private let signpostID: OSSignpostID
    private var metadata: [String: String]
    private var started = false
    
    init(log: OSLog, name: StaticString, metadata: [String: String] = [:]) {
        self.log = log
        self.name = name
        self.signpostID = OSSignpostID(log: log)
        self.metadata = metadata
    }
    
    public func begin() {
        guard !started else { return }
        started = true
        
        if metadata.isEmpty {
            os_signpost(.begin, log: log, name: name, signpostID: signpostID)
        } else {
            let message = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            os_signpost(.begin, log: log, name: name, signpostID: signpostID, "%{public}s", message)
        }
    }
    
    public func end() {
        guard started else { return }
        started = false
        os_signpost(.end, log: log, name: name, signpostID: signpostID)
    }
    
    public func event(_ message: String) {
        os_signpost(.event, log: log, name: name, signpostID: signpostID, "%{public}s", message)
    }
    
    /// Convenience method for measuring a block
    public func measure<T>(_ block: () throws -> T) rethrows -> T {
        begin()
        defer { end() }
        return try block()
    }
    
    /// Async version
    public func measure<T>(_ block: () async throws -> T) async rethrows -> T {
        begin()
        defer { end() }
        return try await block()
    }
}

// MARK: - Default Templates

public struct DefaultInstrumentsTemplates {

    /// Template for app startup profiling
    nonisolated(unsafe) public static let startup = InstrumentsConfig(name: "App Startup") {
        InstrumentsTemplate(
            type: .timeProfiler,
            configuration: [
                "sample_interval": 1000, // microseconds
                "record_waiting_threads": true
            ]
        )
        
        InstrumentsTemplate(
            type: .systemTrace,
            configuration: [
                "record_virtual_memory": true,
                "record_thread_states": true
            ]
        )
        
        InstrumentsTemplate(
            type: .allocations,
            configuration: [
                "track_vm_allocations": true,
                "record_reference_counts": false
            ]
        )
    }
    
    /// Template for UI performance profiling
    nonisolated(unsafe) public static let uiPerformance = InstrumentsConfig(name: "UI Performance") {
        InstrumentsTemplate(
            type: .swiftUIProfiler,
            configuration: [:]
        )
        
        InstrumentsTemplate(
            type: .timeProfiler,
            configuration: [
                "sample_interval": 100,
                "record_waiting_threads": false
            ]
        )
        
        InstrumentsTemplate(
            type: .hangDetection,
            configuration: [
                "hang_threshold": 250 // milliseconds
            ]
        )
        
        InstrumentsTemplate(
            type: .systemTrace,
            configuration: [
                "record_display_refresh": true
            ]
        )
    }
    
    /// Template for memory profiling
    nonisolated(unsafe) public static let memory = InstrumentsConfig(name: "Memory") {
        InstrumentsTemplate(
            type: .allocations,
            configuration: [
                "track_vm_allocations": true,
                "record_reference_counts": true,
                "identify_heap_objects": true
            ]
        )
        
        InstrumentsTemplate(
            type: .leaks,
            configuration: [
                "check_interval": 10 // seconds
            ]
        )
    }
    
    /// Template for network profiling
    nonisolated(unsafe) public static let network = InstrumentsConfig(name: "Network") {
        InstrumentsTemplate(
            type: .networkActivity,
            configuration: [
                "record_request_bodies": false,
                "record_response_bodies": false,
                "track_connections": true
            ]
        )
        
        InstrumentsTemplate(
            type: .timeProfiler,
            configuration: [
                "sample_interval": 1000
            ]
        )
    }
}

#if os(macOS)
// MARK: - Instruments Runner

/// Helper for running Instruments from command line
public struct InstrumentsRunner {

    /// Run Instruments with a specific template
    public static func profile(
        app: String,
        template: InstrumentsTemplate,
        duration: TimeInterval = 10,
        outputPath: String
    ) async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("template.tracetemplate")

        let config = InstrumentsConfig(name: "Benchmark") {
            template
        }

        try config.exportTemplate(to: tempURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "instruments",
            "-t", tempURL.path,
            "-D", outputPath,
            "-l", "\(Int(duration * 1000))",
            app
        ]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw InstrumentsError.profilingFailed(
                exitCode: process.terminationStatus
            )
        }
    }

    /// Parse trace file for metrics
    public static func parseTrace(at path: String) throws -> TraceMetrics {
        // This would use Instruments' export functionality
        // For demo, returning mock data
        return TraceMetrics(
            cpuUsage: 45.2,
            memoryUsage: 120 * 1024 * 1024,
            diskIO: 5 * 1024 * 1024,
            networkIO: 2 * 1024 * 1024
        )
    }
}
#endif

public struct TraceMetrics {
    public let cpuUsage: Double // percentage
    public let memoryUsage: Int64 // bytes
    public let diskIO: Int64 // bytes
    public let networkIO: Int64 // bytes
}

public enum InstrumentsError: LocalizedError {
    case profilingFailed(exitCode: Int32)
    case templateNotFound
    case parseError(String)
    
    public var errorDescription: String? {
        switch self {
        case .profilingFailed(let code):
            return "Instruments profiling failed with exit code: \(code)"
        case .templateNotFound:
            return "Instruments template not found"
        case .parseError(let message):
            return "Failed to parse trace: \(message)"
        }
    }
}