import Foundation
import XCTest
import os.signpost
import SwiftUI

// MARK: - Performance Suite Runner

public final class PerformanceSuiteRunner {
    private let suites: [PerformanceSuite]
    private let configuration: Configuration
    private let signposter = OSSignposter()
    private var results: [SuiteResult] = []
    
    public struct Configuration {
        public let iterations: Int
        public let warmupIterations: Int
        public let enableSignposts: Bool
        public let enableMemoryTracking: Bool
        public let enableDiffTracking: Bool
        public let outputDirectory: URL
        public let baselineURL: URL?
        
        public static let `default` = Configuration(
            iterations: 10,
            warmupIterations: 2,
            enableSignposts: true,
            enableMemoryTracking: true,
            enableDiffTracking: true,
            outputDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("perf-results"),
            baselineURL: nil
        )
    }
    
    public init(suites: [PerformanceSuite], configuration: Configuration = .default) {
        self.suites = suites
        self.configuration = configuration
    }
    
    // MARK: - Running Suites
    
    public func run() async throws -> PerformanceReport {
        // Setup
        try FileManager.default.createDirectory(at: configuration.outputDirectory, withIntermediateDirectories: true)
        
        if configuration.enableSignposts {
            PerformanceTracer.shared.configure(enabled: true)
        }
        
        if configuration.enableDiffTracking {
            ViewDiffTracker.shared.startTracking()
        }
        
        // Run each suite
        for suite in suites {
            let result = try await runSuite(suite)
            results.append(result)
        }
        
        // Generate report
        let report = PerformanceReport(
            results: results,
            configuration: configuration,
            timestamp: Date()
        )
        
        // Save results
        try report.save(to: configuration.outputDirectory.appendingPathComponent("report.json"))
        
        // Compare with baseline if available
        if let baselineURL = configuration.baselineURL {
            let baseline = try PerformanceReport.load(from: baselineURL)
            let comparison = report.compare(with: baseline)
            try comparison.save(to: configuration.outputDirectory.appendingPathComponent("comparison.json"))
        }
        
        return report
    }
    
    private func runSuite(_ suite: PerformanceSuite) async throws -> SuiteResult {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("PerformanceSuite", id: signpostID, "suite: \(suite.name)")
        defer { signposter.endInterval("PerformanceSuite", state) }
        
        var measurements: [Measurement] = []
        
        // Warmup
        for _ in 0..<configuration.warmupIterations {
            _ = try await suite.run()
        }
        
        // Actual measurements
        for iteration in 0..<configuration.iterations {
            signposter.emitEvent("Iteration", id: signpostID, "iteration: \(iteration)")
            
            let memoryBefore = MemoryWarningManager.shared.memoryUsage
            let renderStatsBefore = ViewDiffTracker.shared.renderStats
            
            let start = CFAbsoluteTimeGetCurrent()
            let metrics = try await suite.run()
            let duration = CFAbsoluteTimeGetCurrent() - start
            
            let memoryAfter = MemoryWarningManager.shared.memoryUsage
            let renderStatsAfter = ViewDiffTracker.shared.renderStats
            
            let measurement = Measurement(
                iteration: iteration,
                duration: duration,
                metrics: metrics,
                memoryDelta: Int(memoryAfter.used - memoryBefore.used),
                renderCount: renderStatsAfter.totalRenders - renderStatsBefore.totalRenders,
                unnecessaryRenders: renderStatsAfter.unnecessaryRenders - renderStatsBefore.unnecessaryRenders
            )
            
            measurements.append(measurement)
        }
        
        return SuiteResult(
            name: suite.name,
            measurements: measurements,
            statistics: calculateStatistics(measurements)
        )
    }
    
    private func calculateStatistics(_ measurements: [Measurement]) -> Statistics {
        let durations = measurements.map { $0.duration }
        let sorted = durations.sorted()
        
        return Statistics(
            mean: durations.reduce(0, +) / Double(durations.count),
            median: sorted[sorted.count / 2],
            min: sorted.first ?? 0,
            max: sorted.last ?? 0,
            standardDeviation: calculateStandardDeviation(durations),
            p95: percentile(sorted, 0.95),
            p99: percentile(sorted, 0.99)
        )
    }
    
    private func calculateStandardDeviation(_ values: [Double]) -> Double {
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        let variance = squaredDiffs.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
    
    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        let index = Int(Double(sorted.count - 1) * p)
        return sorted[index]
    }
}

// MARK: - Performance Suite Protocol

public protocol PerformanceSuite {
    var name: String { get }
    func run() async throws -> [String: Double]
}

// MARK: - Built-in Suites

public struct ViewRenderingSuite: PerformanceSuite {
    public let name = "View Rendering"
    private let viewCount: Int
    
    public init(viewCount: Int = 100) {
        self.viewCount = viewCount
    }
    
    public func run() async throws -> [String: Double] {
        var metrics: [String: Double] = [:]
        
        // Measure list rendering
        let listStart = CFAbsoluteTimeGetCurrent()
        _ = renderList()
        metrics["list_render"] = CFAbsoluteTimeGetCurrent() - listStart
        
        // Measure complex view
        let complexStart = CFAbsoluteTimeGetCurrent()
        _ = renderComplexView()
        metrics["complex_view"] = CFAbsoluteTimeGetCurrent() - complexStart
        
        return metrics
    }
    
    @MainActor
    private func renderList() -> some View {
        List(0..<viewCount) { index in
            HStack {
                Image(systemName: "star")
                Text("Item \(index)")
                Spacer()
                Text("Value")
            }
        }
    }
    
    @MainActor
    private func renderComplexView() -> some View {
        VStack {
            ForEach(0..<10) { _ in
                HStack {
                    ForEach(0..<10) { _ in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.gradient)
                            .frame(width: 30, height: 30)
                    }
                }
            }
        }
    }
}

public struct NavigationSuite: PerformanceSuite {
    public let name = "Navigation"
    private let depth: Int
    
    public init(depth: Int = 10) {
        self.depth = depth
    }
    
    public func run() async throws -> [String: Double] {
        var metrics: [String: Double] = [:]
        
        // Measure push performance
        let pushStart = CFAbsoluteTimeGetCurrent()
        for i in 0..<depth {
            PerformanceTracer.shared.traceNavigation(
                from: "Level\(i)",
                to: "Level\(i+1)",
                trigger: .programmatic
            )
        }
        metrics["push_stack"] = CFAbsoluteTimeGetCurrent() - pushStart
        
        // Measure pop performance
        let popStart = CFAbsoluteTimeGetCurrent()
        for i in (0..<depth).reversed() {
            PerformanceTracer.shared.traceNavigation(
                from: "Level\(i+1)",
                to: "Level\(i)",
                trigger: .programmatic
            )
        }
        metrics["pop_stack"] = CFAbsoluteTimeGetCurrent() - popStart
        
        return metrics
    }
}

public struct DataLoadingSuite: PerformanceSuite {
    public let name = "Data Loading"
    private let itemCount: Int
    
    public init(itemCount: Int = 1000) {
        self.itemCount = itemCount
    }
    
    public func run() async throws -> [String: Double] {
        var metrics: [String: Double] = [:]
        
        // Measure JSON decoding
        let jsonData = generateJSON()
        let decodeStart = CFAbsoluteTimeGetCurrent()
        _ = try JSONDecoder().decode([TestItem].self, from: jsonData)
        metrics["json_decode"] = CFAbsoluteTimeGetCurrent() - decodeStart
        
        // Measure cache performance
        let cache = CacheManager()
        let cacheStart = CFAbsoluteTimeGetCurrent()
        for i in 0..<100 {
            cache.set(TestItem(id: i, name: "Item \(i)"), for: "item_\(i)")
        }
        for i in 0..<100 {
            _ = cache.get("item_\(i)", as: TestItem.self)
        }
        metrics["cache_operations"] = CFAbsoluteTimeGetCurrent() - cacheStart
        
        return metrics
    }
    
    private func generateJSON() -> Data {
        let items = (0..<itemCount).map { TestItem(id: $0, name: "Item \($0)") }
        return try! JSONEncoder().encode(items)
    }
    
    private struct TestItem: Codable {
        let id: Int
        let name: String
    }
}

// MARK: - Results

public struct SuiteResult: Codable {
    public let name: String
    public let measurements: [Measurement]
    public let statistics: Statistics
    
    public struct Measurement: Codable {
        public let iteration: Int
        public let duration: TimeInterval
        public let metrics: [String: Double]
        public let memoryDelta: Int
        public let renderCount: Int
        public let unnecessaryRenders: Int
    }
    
    public struct Statistics: Codable {
        public let mean: Double
        public let median: Double
        public let min: Double
        public let max: Double
        public let standardDeviation: Double
        public let p95: Double
        public let p99: Double
    }
}

public struct PerformanceReport: Codable {
    public let results: [SuiteResult]
    public let configuration: ConfigurationData
    public let timestamp: Date
    
    public struct ConfigurationData: Codable {
        public let iterations: Int
        public let warmupIterations: Int
        public let enableSignposts: Bool
        public let enableMemoryTracking: Bool
        public let enableDiffTracking: Bool
    }
    
    init(results: [SuiteResult], configuration: PerformanceSuiteRunner.Configuration, timestamp: Date) {
        self.results = results
        self.configuration = ConfigurationData(
            iterations: configuration.iterations,
            warmupIterations: configuration.warmupIterations,
            enableSignposts: configuration.enableSignposts,
            enableMemoryTracking: configuration.enableMemoryTracking,
            enableDiffTracking: configuration.enableDiffTracking
        )
        self.timestamp = timestamp
    }
    
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
    
    public static func load(from url: URL) throws -> PerformanceReport {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PerformanceReport.self, from: data)
    }
    
    public func compare(with baseline: PerformanceReport) -> PerformanceComparison {
        var regressions: [Regression] = []
        
        for result in results {
            if let baselineResult = baseline.results.first(where: { $0.name == result.name }) {
                let meanDiff = (result.statistics.mean - baselineResult.statistics.mean) / baselineResult.statistics.mean * 100
                if meanDiff > 5 { // 5% regression threshold
                    regressions.append(Regression(
                        suite: result.name,
                        baseline: baselineResult.statistics.mean,
                        current: result.statistics.mean,
                        percentChange: meanDiff
                    ))
                }
            }
        }
        
        return PerformanceComparison(
            baseline: baseline.timestamp,
            current: timestamp,
            regressions: regressions
        )
    }
}

public struct PerformanceComparison: Codable {
    public let baseline: Date
    public let current: Date
    public let regressions: [Regression]
    
    public struct Regression: Codable {
        public let suite: String
        public let baseline: Double
        public let current: Double
        public let percentChange: Double
    }
    
    public var summary: String {
        if regressions.isEmpty {
            return "✅ No performance regressions detected"
        } else {
            return """
            ⚠️ Performance Regressions Detected:
            \(regressions.map { "  - \($0.suite): +\(String(format: "%.1f%%", $0.percentChange))" }.joined(separator: "\n"))
            """
        }
    }
    
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}

// MARK: - XCTest Integration

open class PerformanceXCTestCase: XCTestCase {
    public var suiteRunner: PerformanceSuiteRunner!
    
    open override func setUp() {
        super.setUp()
        
        let suites: [PerformanceSuite] = [
            ViewRenderingSuite(),
            NavigationSuite(),
            DataLoadingSuite()
        ]
        
        suiteRunner = PerformanceSuiteRunner(
            suites: suites,
            configuration: .default
        )
    }
    
    public func testPerformanceSuite() async throws {
        let report = try await suiteRunner.run()
        
        // Check for regressions
        for result in report.results {
            XCTAssertLessThan(
                result.statistics.p95,
                0.1, // 100ms threshold
                "\(result.name) P95 exceeds threshold"
            )
        }
        
        // Export for CI
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf-report-\(Date().timeIntervalSince1970).json")
        try report.save(to: url)
        print("Performance report saved to: \(url.path)")
    }
}