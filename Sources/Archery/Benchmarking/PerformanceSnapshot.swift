import Foundation

// MARK: - Performance Snapshot

/// Captures and compares performance across macro revisions
public struct PerformanceSnapshot: Codable {
    
    public let id: String
    public let timestamp: Date
    public let version: PerformanceVersion
    public let commit: String?
    public let benchmarks: [BenchmarkSnapshot]
    public let metadata: SnapshotMetadata
    
    public init(
        id: String = UUID().uuidString,
        version: PerformanceVersion,
        commit: String? = nil,
        benchmarks: [BenchmarkSnapshot],
        metadata: SnapshotMetadata = SnapshotMetadata()
    ) {
        self.id = id
        self.timestamp = Date()
        self.version = version
        self.commit = commit
        self.benchmarks = benchmarks
        self.metadata = metadata
    }
    
    // MARK: - Comparison
    
    /// Compare with another snapshot
    public func compare(to other: PerformanceSnapshot) -> SnapshotComparison {
        var comparisons: [BenchmarkSnapshotComparison] = []
        
        for benchmark in benchmarks {
            if let otherBenchmark = other.benchmarks.first(where: { $0.name == benchmark.name }) {
                comparisons.append(BenchmarkSnapshotComparison(
                    current: benchmark,
                    baseline: otherBenchmark
                ))
            }
        }
        
        return SnapshotComparison(
            currentSnapshot: self,
            baselineSnapshot: other,
            benchmarkComparisons: comparisons
        )
    }
    
    // MARK: - Persistence
    
    /// Save snapshot to file
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
    
    /// Load snapshot from file
    public static func load(from url: URL) throws -> PerformanceSnapshot {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PerformanceSnapshot.self, from: data)
    }
}

// MARK: - Benchmark Snapshot

public struct BenchmarkSnapshot: Codable {
    public let name: String
    public let iterations: Int
    public let metrics: BenchmarkMetrics
    
    public init(name: String, iterations: Int, metrics: BenchmarkMetrics) {
        self.name = name
        self.iterations = iterations
        self.metrics = metrics
    }
    
    public init(from result: BenchmarkResult) {
        self.name = result.name
        self.iterations = result.iterations
        self.metrics = BenchmarkMetrics(
            mean: result.statistics.mean,
            median: result.statistics.median,
            min: result.statistics.min,
            max: result.statistics.max,
            standardDeviation: result.statistics.standardDeviation,
            percentile95: result.statistics.percentile95,
            memoryPeak: Int64(result.memoryMeasurements.max() ?? 0)
        )
    }
}

public struct BenchmarkMetrics: Codable {
    public let mean: TimeInterval
    public let median: TimeInterval
    public let min: TimeInterval
    public let max: TimeInterval
    public let standardDeviation: TimeInterval
    public let percentile95: TimeInterval
    public let memoryPeak: Int64
}

// MARK: - Snapshot Metadata

public struct SnapshotMetadata: Codable {
    public let platform: String
    public let device: String
    public let osVersion: String
    public let buildConfiguration: String
    public let swiftVersion: String
    public let additionalInfo: [String: String]
    
    public init(
        buildConfiguration: String = "Release",
        additionalInfo: [String: String] = [:]
    ) {
        self.platform = Self.currentPlatform()
        self.device = Self.currentDevice()
        self.osVersion = Self.currentOSVersion()
        self.buildConfiguration = buildConfiguration
        self.swiftVersion = Self.currentSwiftVersion()
        self.additionalInfo = additionalInfo
    }
    
    private static func currentPlatform() -> String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(watchOS)
        return "watchOS"
        #else
        return "Unknown"
        #endif
    }
    
    private static func currentDevice() -> String {
        #if os(iOS)
        return "iPhone"
        #elseif os(tvOS)
        return "Apple TV"
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #elseif os(watchOS)
        return "Apple Watch"
        #elseif os(visionOS)
        return "Apple Vision Pro"
        #else
        return "Unknown"
        #endif
    }
    
    private static func currentOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
    
    private static func currentSwiftVersion() -> String {
        #if swift(>=6.0)
        return "6.0+"
        #elseif swift(>=5.9)
        return "5.9+"
        #elseif swift(>=5.8)
        return "5.8+"
        #else
        return "5.7"
        #endif
    }
}

// MARK: - Performance Version

public struct PerformanceVersion: Codable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let build: String?
    
    public init(major: Int, minor: Int, patch: Int, build: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.build = build
    }
    
    public static func < (lhs: PerformanceVersion, rhs: PerformanceVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

// MARK: - Snapshot Comparison

public struct SnapshotComparison {
    public let currentSnapshot: PerformanceSnapshot
    public let baselineSnapshot: PerformanceSnapshot
    public let benchmarkComparisons: [BenchmarkSnapshotComparison]
    
    public var overallSpeedup: Double {
        guard !benchmarkComparisons.isEmpty else { return 1.0 }
        
        let totalCurrent = benchmarkComparisons.reduce(0) { $0 + $1.current.metrics.mean }
        let totalBaseline = benchmarkComparisons.reduce(0) { $0 + $1.baseline.metrics.mean }
        
        return totalBaseline / totalCurrent
    }
    
    public var improvements: [BenchmarkSnapshotComparison] {
        benchmarkComparisons.filter { $0.speedup > 1.05 }
    }
    
    public var regressions: [BenchmarkSnapshotComparison] {
        benchmarkComparisons.filter { $0.speedup < 0.95 }
    }
    
    public var summary: String {
        """
        Performance Snapshot Comparison
        ================================
        Current: v\(currentSnapshot.version.major).\(currentSnapshot.version.minor).\(currentSnapshot.version.patch)
        Baseline: v\(baselineSnapshot.version.major).\(baselineSnapshot.version.minor).\(baselineSnapshot.version.patch)
        
        Overall: \(String(format: "%.2fx", overallSpeedup)) \(overallSpeedup > 1.05 ? "🚀" : overallSpeedup < 0.95 ? "🐌" : "➡️")
        
        Improvements: \(improvements.count)
        Regressions: \(regressions.count)
        Unchanged: \(benchmarkComparisons.count - improvements.count - regressions.count)
        
        Details:
        \(benchmarkComparisons.map { $0.summary }.joined(separator: "\n"))
        """
    }
    
    public func generateReport() -> SnapshotPerformanceReport {
        SnapshotPerformanceReport(
            comparison: self,
            timestamp: Date()
        )
    }
}

public struct BenchmarkSnapshotComparison {
    public let current: BenchmarkSnapshot
    public let baseline: BenchmarkSnapshot
    
    public var speedup: Double {
        baseline.metrics.mean / current.metrics.mean
    }
    
    public var percentChange: Double {
        ((current.metrics.mean - baseline.metrics.mean) / baseline.metrics.mean) * 100
    }
    
    public var memoryChange: Int64 {
        current.metrics.memoryPeak - baseline.metrics.memoryPeak
    }
    
    public var summary: String {
        let emoji = speedup > 1.05 ? "🚀" : speedup < 0.95 ? "🐌" : "➡️"
        return """
          \(emoji) \(current.name):
            Time: \(String(format: "%.3fms", current.metrics.mean * 1000)) → \(String(format: "%.3fms", baseline.metrics.mean * 1000)) (\(String(format: "%+.1f%%", percentChange)))
            Memory: \(formatBytes(current.metrics.memoryPeak)) → \(formatBytes(baseline.metrics.memoryPeak)) (\(formatBytes(memoryChange, signed: true)))
        """
    }
    
    private func formatBytes(_ bytes: Int64, signed: Bool = false) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        
        if signed && bytes > 0 {
            return "+" + formatter.string(fromByteCount: bytes)
        }
        return formatter.string(fromByteCount: abs(bytes))
    }
}

// MARK: - Snapshot Performance Report

public struct SnapshotPerformanceReport {
    public let comparison: SnapshotComparison
    public let timestamp: Date
    
    /// Generate HTML report
    public func generateHTML() -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Performance Report</title>
            <style>
                body { font-family: system-ui; margin: 2em; }
                .improvement { color: green; }
                .regression { color: red; }
                .unchanged { color: gray; }
                table { width: 100%; border-collapse: collapse; }
                th, td { padding: 8px; text-align: left; border-bottom: 1px solid #ddd; }
                th { background: #f0f0f0; }
            </style>
        </head>
        <body>
            <h1>Performance Report</h1>
            <p>Generated: \(timestamp)</p>
            
            <h2>Summary</h2>
            <p>Overall speedup: <strong>\(String(format: "%.2fx", comparison.overallSpeedup))</strong></p>
            
            <h2>Benchmarks</h2>
            <table>
                <thead>
                    <tr>
                        <th>Benchmark</th>
                        <th>Current</th>
                        <th>Baseline</th>
                        <th>Change</th>
                        <th>Memory</th>
                    </tr>
                </thead>
                <tbody>
                    \(comparison.benchmarkComparisons.map { comp in
                        let changeClass = comp.speedup > 1.05 ? "improvement" : comp.speedup < 0.95 ? "regression" : "unchanged"
                        return """
                        <tr>
                            <td>\(comp.current.name)</td>
                            <td>\(String(format: "%.3fms", comp.current.metrics.mean * 1000))</td>
                            <td>\(String(format: "%.3fms", comp.baseline.metrics.mean * 1000))</td>
                            <td class="\(changeClass)">\(String(format: "%+.1f%%", comp.percentChange))</td>
                            <td>\(formatBytes(comp.memoryChange))</td>
                        </tr>
                        """
                    }.joined(separator: "\n"))
                </tbody>
            </table>
        </body>
        </html>
        """
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Snapshot Storage

/// Manages performance snapshot storage
public final class SnapshotStorage {
    private let baseURL: URL
    
    public init(baseURL: URL? = nil) {
        self.baseURL = baseURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PerformanceSnapshots")
    }
    
    /// Save snapshot
    public func save(_ snapshot: PerformanceSnapshot) throws {
        try FileManager.default.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true
        )
        
        let filename = "\(snapshot.version.major).\(snapshot.version.minor).\(snapshot.version.patch).json"
        let url = baseURL.appendingPathComponent(filename)
        
        try snapshot.save(to: url)
    }
    
    /// Load snapshot for version
    public func load(version: PerformanceVersion) throws -> PerformanceSnapshot {
        let filename = "\(version.major).\(version.minor).\(version.patch).json"
        let url = baseURL.appendingPathComponent(filename)
        
        return try PerformanceSnapshot.load(from: url)
    }
    
    /// List all snapshots
    public func listSnapshots() throws -> [PerformanceSnapshot] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        
        return urls.compactMap { url -> PerformanceSnapshot? in
            guard url.pathExtension == "json" else { return nil }
            return try? PerformanceSnapshot.load(from: url)
        }
    }
    
    /// Find baseline snapshot
    public func findBaseline(for version: PerformanceVersion) throws -> PerformanceSnapshot? {
        let snapshots = try listSnapshots()
        
        // Find the most recent snapshot before this version
        return snapshots
            .filter { $0.version < version }
            .sorted { $0.version > $1.version }
            .first
    }
}

// MARK: - Host Helper (macOS)

#if os(macOS)
import IOKit

struct Host {
    static func current() -> Host {
        Host()
    }
    
    var localizedName: String? {
        return ProcessInfo.processInfo.hostName
    }
}
#endif

// MARK: - UIDevice Helper (iOS/tvOS/watchOS)

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#endif