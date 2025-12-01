import Foundation
import QuartzCore
import os.signpost

// MARK: - Benchmark Harness

/// Microbenchmark harness for measuring performance
public final class BenchmarkHarness {
    
    private let name: String
    private let iterations: Int
    private let warmupIterations: Int
    private let signpostLog: OSLog
    
    public init(
        name: String,
        iterations: Int = 1000,
        warmupIterations: Int = 100
    ) {
        self.name = name
        self.iterations = iterations
        self.warmupIterations = warmupIterations
        self.signpostLog = OSLog(subsystem: "com.archery.benchmarks", category: name)
    }
    
    // MARK: - Benchmark Execution
    
    /// Run a benchmark and collect metrics
    @discardableResult
    public func measure<T>(
        _ name: String,
        setUp: (() -> Void)? = nil,
        tearDown: (() -> Void)? = nil,
        block: () throws -> T
    ) rethrows -> BenchmarkResult {
        // Warmup
        for _ in 0..<warmupIterations {
            setUp?()
            _ = try block()
            tearDown?()
        }
        
        // Actual measurements
        var measurements: [TimeInterval] = []
        var memoryMeasurements: [Int64] = []
        
        let signpostID = OSSignpostID(log: signpostLog)
        
        for i in 0..<iterations {
            setUp?()
            
            // Memory before
            let memBefore = currentMemoryUsage()
            
            // Time measurement
            os_signpost(.begin, log: signpostLog, name: "Benchmark", signpostID: signpostID)
            let start = CACurrentMediaTime()
            
            _ = try block()
            
            let end = CACurrentMediaTime()
            os_signpost(.end, log: signpostLog, name: "Benchmark", signpostID: signpostID)
            
            // Memory after
            let memAfter = currentMemoryUsage()
            
            measurements.append(end - start)
            memoryMeasurements.append(memAfter - memBefore)
            
            tearDown?()
            
            // Occasional GC to reduce noise
            if i % 100 == 0 {
                autoreleasepool { }
            }
        }
        
        return BenchmarkResult(
            name: name,
            iterations: iterations,
            measurements: measurements,
            memoryMeasurements: memoryMeasurements
        )
    }
    
    /// Run async benchmark
    @discardableResult
    public func measureAsync<T>(
        _ name: String,
        setUp: (() async -> Void)? = nil,
        tearDown: (() async -> Void)? = nil,
        block: () async throws -> T
    ) async rethrows -> BenchmarkResult {
        // Warmup
        for _ in 0..<warmupIterations {
            await setUp?()
            _ = try await block()
            await tearDown?()
        }
        
        // Actual measurements
        var measurements: [TimeInterval] = []
        var memoryMeasurements: [Int64] = []
        
        for i in 0..<iterations {
            await setUp?()
            
            let memBefore = currentMemoryUsage()
            let start = CACurrentMediaTime()
            
            _ = try await block()
            
            let end = CACurrentMediaTime()
            let memAfter = currentMemoryUsage()
            
            measurements.append(end - start)
            memoryMeasurements.append(memAfter - memBefore)
            
            await tearDown?()
            
            if i % 100 == 0 {
                await Task.yield()
            }
        }
        
        return BenchmarkResult(
            name: name,
            iterations: iterations,
            measurements: measurements,
            memoryMeasurements: memoryMeasurements
        )
    }
    
    // MARK: - Suite Execution
    
    /// Run a suite of benchmarks
    public func suite(_ name: String, @BenchmarkBuilder benchmarks: () -> [Benchmark]) -> BenchmarkSuiteResult {
        let benchmarkList = benchmarks()
        var results: [BenchmarkResult] = []
        
        print("Running benchmark suite: \(name)")
        print(String(repeating: "=", count: 50))
        
        for benchmark in benchmarkList {
            print("Running: \(benchmark.name)...", terminator: " ")
            
            let result = benchmark.run()
            results.append(result)
            
            print("✓ \(String(format: "%.3f", result.statistics.mean * 1000))ms")
        }
        
        return BenchmarkSuiteResult(
            name: name,
            timestamp: Date(),
            results: results
        )
    }
    
    // MARK: - Memory Measurement
    
    private func currentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}

// MARK: - Benchmark Result

public struct BenchmarkResult {
    public let name: String
    public let iterations: Int
    public let measurements: [TimeInterval]
    public let memoryMeasurements: [Int64]
    public let statistics: Statistics
    
    public init(
        name: String,
        iterations: Int,
        measurements: [TimeInterval],
        memoryMeasurements: [Int64]
    ) {
        self.name = name
        self.iterations = iterations
        self.measurements = measurements
        self.memoryMeasurements = memoryMeasurements
        self.statistics = Statistics(measurements: measurements)
    }
    
    public var summary: String {
        """
        Benchmark: \(name)
        Iterations: \(iterations)
        
        Time:
          Mean: \(String(format: "%.3f", statistics.mean * 1000))ms
          Median: \(String(format: "%.3f", statistics.median * 1000))ms
          Min: \(String(format: "%.3f", statistics.min * 1000))ms
          Max: \(String(format: "%.3f", statistics.max * 1000))ms
          Std Dev: \(String(format: "%.3f", statistics.standardDeviation * 1000))ms
          95th %ile: \(String(format: "%.3f", statistics.percentile95 * 1000))ms
        
        Memory:
          Mean: \(formatBytes(Int64(memoryMeasurements.reduce(0, +) / memoryMeasurements.count)))
          Max: \(formatBytes(memoryMeasurements.max() ?? 0))
        """
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Statistics

public struct Statistics {
    public let measurements: [TimeInterval]
    public let mean: TimeInterval
    public let median: TimeInterval
    public let min: TimeInterval
    public let max: TimeInterval
    public let standardDeviation: TimeInterval
    public let percentile95: TimeInterval
    
    public init(measurements: [TimeInterval]) {
        self.measurements = measurements
        
        let sorted = measurements.sorted()
        
        self.mean = measurements.reduce(0, +) / Double(measurements.count)
        self.median = sorted[sorted.count / 2]
        self.min = sorted.first ?? 0
        self.max = sorted.last ?? 0
        
        let variance = measurements.map { pow($0 - mean, 2) }.reduce(0, +) / Double(measurements.count)
        self.standardDeviation = sqrt(variance)
        
        let index95 = Int(Double(sorted.count) * 0.95)
        self.percentile95 = sorted[min(index95, sorted.count - 1)]
    }
}

// MARK: - Benchmark Suite Result

public struct BenchmarkSuiteResult {
    public let name: String
    public let timestamp: Date
    public let results: [BenchmarkResult]
    
    public var summary: String {
        """
        Benchmark Suite: \(name)
        Date: \(timestamp)
        
        Results:
        \(results.map { "  - \($0.name): \(String(format: "%.3f", $0.statistics.mean * 1000))ms" }.joined(separator: "\n"))
        """
    }
    
    public func compare(to baseline: BenchmarkSuiteResult) -> ComparisonReport {
        var comparisons: [BenchmarkComparison] = []
        
        for result in results {
            if let baselineResult = baseline.results.first(where: { $0.name == result.name }) {
                comparisons.append(BenchmarkComparison(
                    name: result.name,
                    current: result,
                    baseline: baselineResult
                ))
            }
        }
        
        return ComparisonReport(comparisons: comparisons)
    }
}

// MARK: - Benchmark Comparison

public struct BenchmarkComparison {
    public let name: String
    public let current: BenchmarkResult
    public let baseline: BenchmarkResult
    
    public var speedup: Double {
        baseline.statistics.mean / current.statistics.mean
    }
    
    public var percentChange: Double {
        ((current.statistics.mean - baseline.statistics.mean) / baseline.statistics.mean) * 100
    }
    
    public var summary: String {
        let emoji = speedup > 1.05 ? "🚀" : speedup < 0.95 ? "🐌" : "➡️"
        return """
        \(emoji) \(name):
          Current: \(String(format: "%.3f", current.statistics.mean * 1000))ms
          Baseline: \(String(format: "%.3f", baseline.statistics.mean * 1000))ms
          Change: \(String(format: "%+.1f%%", percentChange)) (\(String(format: "%.2fx", speedup)))
        """
    }
}

public struct ComparisonReport {
    public let comparisons: [BenchmarkComparison]
    
    public var summary: String {
        """
        Performance Comparison Report
        =============================
        
        \(comparisons.map { $0.summary }.joined(separator: "\n\n"))
        
        Summary:
          Improvements: \(comparisons.filter { $0.speedup > 1.05 }.count)
          Regressions: \(comparisons.filter { $0.speedup < 0.95 }.count)
          Unchanged: \(comparisons.filter { $0.speedup >= 0.95 && $0.speedup <= 1.05 }.count)
        """
    }
}

// MARK: - Benchmark Builder

@resultBuilder
public struct BenchmarkBuilder {
    public static func buildBlock(_ benchmarks: Benchmark...) -> [Benchmark] {
        benchmarks
    }
}

// MARK: - Benchmark Type

public struct Benchmark {
    public let name: String
    public let run: () -> BenchmarkResult
    
    public init(_ name: String, run: @escaping () -> BenchmarkResult) {
        self.name = name
        self.run = run
    }
}

// MARK: - Common Benchmarks

public struct CommonBenchmarks {
    
    /// Benchmark array operations
    public static func arrayOperations(size: Int = 10000) -> Benchmark {
        Benchmark("Array Operations (size: \(size))") {
            let harness = BenchmarkHarness(name: "array")
            
            return harness.measure("Array append") {
                var array: [Int] = []
                for i in 0..<size {
                    array.append(i)
                }
            }
        }
    }
    
    /// Benchmark dictionary operations
    public static func dictionaryOperations(size: Int = 10000) -> Benchmark {
        Benchmark("Dictionary Operations (size: \(size))") {
            let harness = BenchmarkHarness(name: "dictionary")
            
            return harness.measure("Dictionary insert") {
                var dict: [String: Int] = [:]
                for i in 0..<size {
                    dict["key\(i)"] = i
                }
            }
        }
    }
    
    /// Benchmark string operations
    public static func stringOperations(iterations: Int = 1000) -> Benchmark {
        Benchmark("String Operations") {
            let harness = BenchmarkHarness(name: "string", iterations: iterations)
            
            return harness.measure("String concatenation") {
                var result = ""
                for i in 0..<100 {
                    result += "String \(i) "
                }
            }
        }
    }
}

// MARK: - Signpost Helpers

public extension OSSignpostID {
    static func exclusive() -> OSSignpostID {
        OSSignpostID(log: .default, object: NSObject())
    }
}

public extension OSLog {
    static let benchmarks = OSLog(subsystem: "com.archery.benchmarks", category: "performance")
}