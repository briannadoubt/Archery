import XCTest
import SwiftUI
@testable import Archery

final class BenchmarkSuite: XCTestCase {
    
    // MARK: - Container Lookup Benchmarks

    func testEnvContainerLookup() {
        let harness = BenchmarkHarness(name: "EnvContainer")

        // Setup container with a factory
        let container = EnvContainer()
        container.registerFactory { MockService(id: 42) }

        let result = harness.measure("Container Lookup") {
            for _ in 0..<100 {
                _ = container.resolve() as MockService?
            }
        }

        print(result.summary)
        
        // Validate against budget (relaxed for CI variability)
        let budget = PerformanceBudget(name: "Container") {
            MaximumTimeConstraint(
                name: "Lookup Time",
                threshold: 0.1, // 100ms for 100 lookups (generous for CI)
                metric: .mean
            )
        }

        let validation = budget.validate(result)
        XCTAssertTrue(validation.passed, validation.details)
    }
    
    // MARK: - Repository Caching Benchmarks
    
    func testRepositoryCaching() async {
        let harness = BenchmarkHarness(name: "Repository")
        
        // Create mock repository with caching
        let repository = MockRepository()
        
        // Warm cache
        _ = try? await repository.fetchData(id: "test")
        
        let result = await harness.measureAsync("Cache Hit") {
            _ = try? await repository.fetchData(id: "test")
        }
        
        print(result.summary)
        
        // Should be very fast for cache hits
        XCTAssertLessThan(result.statistics.mean, 0.0001) // < 0.1ms
    }
    
    // MARK: - View Rendering Benchmarks
    
    @MainActor
    func testViewRendering() {
        _ = BenchmarkHarness(name: "View Rendering")

        measure {
            // Measure SwiftUI view creation
            _ = ComplexView()
                .frame(width: 375, height: 812)
        }
    }
    
    // MARK: - State Machine Benchmarks
    
    func testStateMachineTransitions() {
        let harness = BenchmarkHarness(name: "State Machine")
        
        enum TestAction {
            case increment, decrement, reset
        }
        
        let stateMachine = StateMachine<Int, TestAction>(
            initialState: 0,
            transition: { state, action in
                switch action {
                case .increment: return state + 1
                case .decrement: return state - 1
                case .reset: return 0
                }
            }
        )
        
        let result = harness.measure("State Transitions") {
            var state = 0
            for _ in 0..<100 {
                state = stateMachine.transition(state, .increment) ?? state
                state = stateMachine.transition(state, .decrement) ?? state
            }
        }
        
        print(result.summary)
    }
    
    // MARK: - Full Benchmark Suite
    
    func testFullBenchmarkSuite() {
        let harness = BenchmarkHarness(name: "Archery")
        
        let suite = harness.suite("Archery Performance") {
            CommonBenchmarks.arrayOperations(size: 10000)
            CommonBenchmarks.dictionaryOperations(size: 10000)
            CommonBenchmarks.stringOperations(iterations: 1000)
            
            Benchmark("Custom Operation") {
                harness.measure("Heavy Computation") {
                    var result = 0
                    for i in 0..<1000000 {
                        result += i
                    }
                }
            }
        }
        
        print(suite.summary)
        
        // Save snapshot
        let snapshot = PerformanceSnapshot(
            version: PerformanceVersion(major: 1, minor: 0, patch: 0),
            benchmarks: suite.results.map { BenchmarkSnapshot(from: $0) }
        )
        
        let storage = SnapshotStorage()
        try? storage.save(snapshot)
    }
    
    // MARK: - Performance Budget Tests
    
    func testPerformanceBudgetEnforcement() {
        // Create sample benchmark result
        let result = BenchmarkResult(
            name: "Test Operation",
            iterations: 1000,
            measurements: Array(repeating: 0.01, count: 1000), // 10ms each
            memoryMeasurements: Array(repeating: 1024 * 1024, count: 1000) // 1MB each
        )
        
        // Test with strict budget
        let strictBudget = PerformanceBudget(name: "Strict") {
            MaximumTimeConstraint(
                name: "Max Time",
                threshold: 0.005, // 5ms
                metric: .mean
            )
            
            MaximumMemoryConstraint(
                name: "Max Memory",
                threshold: 512 * 1024 // 512KB
            )
        }
        
        let validation = strictBudget.validate(result)
        XCTAssertFalse(validation.passed)
        XCTAssertEqual(validation.violations.count, 2)
        
        // Test with relaxed budget
        let relaxedBudget = PerformanceBudget(name: "Relaxed") {
            MaximumTimeConstraint(
                name: "Max Time",
                threshold: 0.02, // 20ms
                metric: .mean
            )
            
            MaximumMemoryConstraint(
                name: "Max Memory",
                threshold: 2 * 1024 * 1024 // 2MB
            )
        }
        
        let relaxedValidation = relaxedBudget.validate(result)
        XCTAssertTrue(relaxedValidation.passed)
    }
    
    // MARK: - Regression Detection Tests
    
    func testRegressionDetection() {
        // Create baseline result
        let baseline = BenchmarkResult(
            name: "Operation",
            iterations: 100,
            measurements: Array(repeating: 0.01, count: 100), // 10ms
            memoryMeasurements: []
        )
        
        // Create current result with regression
        let current = BenchmarkResult(
            name: "Operation",
            iterations: 100,
            measurements: Array(repeating: 0.015, count: 100), // 15ms (50% slower)
            memoryMeasurements: []
        )
        
        let budget = PerformanceBudget(name: "Regression") {
            RegressionConstraint(
                threshold: 10.0, // Allow 10% regression
                baseline: baseline
            )
        }
        
        let validation = budget.validate(current)
        XCTAssertFalse(validation.passed)
        XCTAssertEqual(validation.violations.count, 1)
    }
    
    // MARK: - Snapshot Comparison Tests
    
    func testSnapshotComparison() {
        // Create baseline snapshot
        let baselineMetrics = BenchmarkMetrics(
            mean: 0.01,
            median: 0.01,
            min: 0.008,
            max: 0.012,
            standardDeviation: 0.001,
            percentile95: 0.011,
            memoryPeak: 1024 * 1024
        )
        
        let baselineBenchmark = BenchmarkSnapshot(
            name: "Test",
            iterations: 1000,
            metrics: baselineMetrics
        )
        
        let baselineSnapshot = PerformanceSnapshot(
            version: PerformanceVersion(major: 1, minor: 0, patch: 0),
            benchmarks: [baselineBenchmark]
        )
        
        // Create improved snapshot
        let improvedMetrics = BenchmarkMetrics(
            mean: 0.008, // 20% faster
            median: 0.008,
            min: 0.006,
            max: 0.010,
            standardDeviation: 0.001,
            percentile95: 0.009,
            memoryPeak: 900 * 1024
        )
        
        let improvedBenchmark = BenchmarkSnapshot(
            name: "Test",
            iterations: 1000,
            metrics: improvedMetrics
        )
        
        let improvedSnapshot = PerformanceSnapshot(
            version: PerformanceVersion(major: 1, minor: 1, patch: 0),
            benchmarks: [improvedBenchmark]
        )
        
        // Compare snapshots
        let comparison = improvedSnapshot.compare(to: baselineSnapshot)
        
        XCTAssertGreaterThan(comparison.overallSpeedup, 1.0)
        XCTAssertEqual(comparison.improvements.count, 1)
        XCTAssertEqual(comparison.regressions.count, 0)
        
        print(comparison.summary)
    }
    
    // MARK: - Instruments Integration Tests
    
    func testInstrumentsSignposts() async {
        let interval = SignpostMarkers.custom("Test Operation")

        let result: ()? = await interval.measure {
            // Simulate work
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        XCTAssertNotNil(result)
    }
    
    func testInstrumentsTemplateExport() throws {
        let config = DefaultInstrumentsTemplates.startup
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test.tracetemplate")
        
        try config.exportTemplate(to: tempURL)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }
}

// MARK: - Mock Types

struct MockService {
    let id: Int
}

class MockRepository {
    private var cache: [String: String] = [:]
    
    func fetchData(id: String) async throws -> String {
        if let cached = cache[id] {
            return cached
        }
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        let data = "Data for \(id)"
        cache[id] = data
        return data
    }
}

struct ComplexView: View {
    var body: some View {
        VStack {
            ForEach(0..<100) { i in
                HStack {
                    Text("Row \(i)")
                    Spacer()
                    Image(systemName: "star")
                }
            }
        }
    }
}