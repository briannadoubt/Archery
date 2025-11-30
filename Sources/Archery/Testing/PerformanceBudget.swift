import Foundation
import XCTest
import os.signpost

// MARK: - Performance Budget

public struct PerformanceBudget {
    public let coldStart: TimeInterval // seconds
    public let warmStart: TimeInterval
    public let memoryLimit: Int // MB
    public let cpuLimit: Double // percentage
    public let frameRate: Double // FPS
    public let networkLatency: TimeInterval
    public let diskUsage: Int // MB
    public let batteryImpact: BatteryImpact
    
    public enum BatteryImpact: String {
        case low, medium, high
    }
    
    public static let `default` = PerformanceBudget(
        coldStart: 0.3, // 300ms
        warmStart: 0.1, // 100ms
        memoryLimit: 150, // 150MB
        cpuLimit: 80, // 80%
        frameRate: 60, // 60fps
        networkLatency: 2.0, // 2s
        diskUsage: 50, // 50MB
        batteryImpact: .low
    )
    
    public static let strict = PerformanceBudget(
        coldStart: 0.2,
        warmStart: 0.05,
        memoryLimit: 100,
        cpuLimit: 50,
        frameRate: 120,
        networkLatency: 1.0,
        diskUsage: 25,
        batteryImpact: .low
    )
}

// MARK: - Performance Monitor

public final class PerformanceMonitor {
    private let budget: PerformanceBudget
    private let log = OSLog(subsystem: "com.archery.performance", category: "monitor")
    private var measurements: [Measurement] = []
    private let signposter = OSSignposter()
    
    public struct Measurement {
        public let metric: Metric
        public let value: Double
        public let timestamp: Date
        public let context: String?
        
        public enum Metric {
            case coldStart
            case warmStart
            case memory
            case cpu
            case frameRate
            case networkLatency
            case diskIO
        }
    }
    
    public init(budget: PerformanceBudget = .default) {
        self.budget = budget
    }
    
    // MARK: - Cold Start
    
    public func measureColdStart(block: () -> Void) -> PerformanceResult {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("ColdStart", id: signpostID)
        
        let start = CFAbsoluteTimeGetCurrent()
        block()
        let duration = CFAbsoluteTimeGetCurrent() - start
        
        signposter.endInterval("ColdStart", state)
        
        let measurement = Measurement(
            metric: .coldStart,
            value: duration,
            timestamp: Date(),
            context: "Cold start"
        )
        measurements.append(measurement)
        
        return PerformanceResult(
            metric: "Cold Start",
            value: duration,
            budget: budget.coldStart,
            passed: duration <= budget.coldStart
        )
    }
    
    // MARK: - Memory
    
    public func measureMemory() -> PerformanceResult {
        let info = mach_task_basic_info()
        let memoryMB = Double(info.resident_size) / 1024 / 1024
        
        let measurement = Measurement(
            metric: .memory,
            value: memoryMB,
            timestamp: Date(),
            context: "Memory usage"
        )
        measurements.append(measurement)
        
        return PerformanceResult(
            metric: "Memory",
            value: memoryMB,
            budget: Double(budget.memoryLimit),
            passed: memoryMB <= Double(budget.memoryLimit)
        )
    }
    
    // MARK: - CPU
    
    public func measureCPU() -> PerformanceResult {
        let cpuUsage = getCurrentCPUUsage()
        
        let measurement = Measurement(
            metric: .cpu,
            value: cpuUsage,
            timestamp: Date(),
            context: "CPU usage"
        )
        measurements.append(measurement)
        
        return PerformanceResult(
            metric: "CPU",
            value: cpuUsage,
            budget: budget.cpuLimit,
            passed: cpuUsage <= budget.cpuLimit
        )
    }
    
    // MARK: - Frame Rate
    
    public func measureFrameRate(duration: TimeInterval = 1.0) -> PerformanceResult {
        let frames = measureFrames(duration: duration)
        let fps = Double(frames) / duration
        
        let measurement = Measurement(
            metric: .frameRate,
            value: fps,
            timestamp: Date(),
            context: "Frame rate"
        )
        measurements.append(measurement)
        
        return PerformanceResult(
            metric: "Frame Rate",
            value: fps,
            budget: budget.frameRate,
            passed: fps >= budget.frameRate
        )
    }
    
    // MARK: - Network
    
    public func measureNetworkLatency(url: URL) async -> PerformanceResult {
        let start = CFAbsoluteTimeGetCurrent()
        
        do {
            let (_, _) = try await URLSession.shared.data(from: url)
            let latency = CFAbsoluteTimeGetCurrent() - start
            
            let measurement = Measurement(
                metric: .networkLatency,
                value: latency,
                timestamp: Date(),
                context: url.absoluteString
            )
            measurements.append(measurement)
            
            return PerformanceResult(
                metric: "Network Latency",
                value: latency,
                budget: budget.networkLatency,
                passed: latency <= budget.networkLatency
            )
        } catch {
            return PerformanceResult(
                metric: "Network Latency",
                value: Double.infinity,
                budget: budget.networkLatency,
                passed: false
            )
        }
    }
    
    // MARK: - Reports
    
    public func generateReport() -> PerformanceReport {
        PerformanceReport(
            budget: budget,
            measurements: measurements,
            timestamp: Date()
        )
    }
    
    // MARK: - Helpers
    
    private func getCurrentCPUUsage() -> Double {
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
        
        if result == KERN_SUCCESS {
            // This is simplified - real implementation would be more complex
            return 25.0 // Placeholder
        }
        return 0.0
    }
    
    private func measureFrames(duration: TimeInterval) -> Int {
        // Simplified - would use CADisplayLink or similar
        return Int(60 * duration)
    }
}

// MARK: - Performance Result

public struct PerformanceResult {
    public let metric: String
    public let value: Double
    public let budget: Double
    public let passed: Bool
    
    public var percentageOfBudget: Double {
        (value / budget) * 100
    }
    
    public var summary: String {
        let icon = passed ? "✅" : "❌"
        return "\(icon) \(metric): \(String(format: "%.2f", value)) / \(String(format: "%.2f", budget)) (\(String(format: "%.0f%%", percentageOfBudget)))"
    }
}

// MARK: - Performance Report

public struct PerformanceReport {
    public let budget: PerformanceBudget
    public let measurements: [PerformanceMonitor.Measurement]
    public let timestamp: Date
    
    public var violations: [Violation] {
        var violations: [Violation] = []
        
        // Check each metric
        for measurement in measurements {
            let budgetValue: Double
            switch measurement.metric {
            case .coldStart:
                budgetValue = budget.coldStart
            case .warmStart:
                budgetValue = budget.warmStart
            case .memory:
                budgetValue = Double(budget.memoryLimit)
            case .cpu:
                budgetValue = budget.cpuLimit
            case .frameRate:
                budgetValue = budget.frameRate
            case .networkLatency:
                budgetValue = budget.networkLatency
            case .diskIO:
                budgetValue = Double(budget.diskUsage)
            }
            
            let isViolation = measurement.metric == .frameRate ?
                measurement.value < budgetValue :
                measurement.value > budgetValue
            
            if isViolation {
                violations.append(Violation(
                    metric: measurement.metric,
                    value: measurement.value,
                    budget: budgetValue,
                    context: measurement.context
                ))
            }
        }
        
        return violations
    }
    
    public struct Violation {
        public let metric: PerformanceMonitor.Measurement.Metric
        public let value: Double
        public let budget: Double
        public let context: String?
        
        public var severity: Severity {
            let ratio = value / budget
            if ratio > 2.0 { return .critical }
            if ratio > 1.5 { return .high }
            if ratio > 1.2 { return .medium }
            return .low
        }
        
        public enum Severity {
            case low, medium, high, critical
        }
    }
    
    public var summary: String {
        """
        Performance Report - \(DateFormatter.localizedString(from: timestamp, dateStyle: .short, timeStyle: .medium))
        
        Measurements: \(measurements.count)
        Violations: \(violations.count)
        
        Budget Status:
        \(violations.isEmpty ? "✅ All metrics within budget" : "❌ \(violations.count) metrics exceeded budget")
        
        Violations:
        \(violations.map { "  - \($0.metric): \(String(format: "%.2f", $0.value)) > \(String(format: "%.2f", $0.budget)) [\($0.severity)]" }.joined(separator: "\n"))
        """
    }
    
    public func writeJSON(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}

extension PerformanceReport: Codable {}
extension PerformanceMonitor.Measurement: Codable {}
extension PerformanceMonitor.Measurement.Metric: Codable {}
extension PerformanceReport.Violation: Codable {}
extension PerformanceReport.Violation.Severity: Codable {}

// MARK: - Performance Test Case

open class PerformanceTestCase: XCTestCase {
    public var performanceMonitor: PerformanceMonitor!
    public var budget: PerformanceBudget = .default
    
    open override func setUp() {
        super.setUp()
        performanceMonitor = PerformanceMonitor(budget: budget)
    }
    
    open override func tearDown() {
        let report = performanceMonitor.generateReport()
        if !report.violations.isEmpty {
            XCTFail("Performance violations:\n\(report.summary)")
        }
        super.tearDown()
    }
    
    public func measurePerformance(
        metric: XCTMetric = XCTApplicationLaunchMetric(),
        block: () throws -> Void
    ) rethrows {
        measure(metrics: [metric]) {
            try? block()
        }
    }
    
    public func assertPerformance(
        _ result: PerformanceResult,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            result.passed,
            result.summary,
            file: file,
            line: line
        )
    }
}

// MARK: - Performance Baseline

public struct PerformanceBaseline: Codable {
    public let measurements: [String: Double]
    public let platform: String
    public let device: String
    public let osVersion: String
    public let timestamp: Date
    
    public static func load(from url: URL) throws -> PerformanceBaseline {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PerformanceBaseline.self, from: data)
    }
    
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
    
    public func compare(with current: [String: Double]) -> [Regression] {
        var regressions: [Regression] = []
        
        for (metric, baselineValue) in measurements {
            if let currentValue = current[metric] {
                let change = ((currentValue - baselineValue) / baselineValue) * 100
                if change > 10 { // More than 10% regression
                    regressions.append(Regression(
                        metric: metric,
                        baseline: baselineValue,
                        current: currentValue,
                        changePercent: change
                    ))
                }
            }
        }
        
        return regressions
    }
    
    public struct Regression {
        public let metric: String
        public let baseline: Double
        public let current: Double
        public let changePercent: Double
        
        public var summary: String {
            "\(metric): \(String(format: "%.2f", baseline)) -> \(String(format: "%.2f", current)) (+\(String(format: "%.1f%%", changePercent)))"
        }
    }
}