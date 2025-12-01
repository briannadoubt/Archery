import Foundation

// MARK: - Performance Budget

/// Defines and enforces performance budgets for CI
public struct PerformanceBudget {
    
    public let name: String
    public let constraints: [PerformanceConstraint]
    
    public init(name: String, @ConstraintBuilder constraints: () -> [PerformanceConstraint]) {
        self.name = name
        self.constraints = constraints()
    }
    
    // MARK: - Validation
    
    /// Validate benchmark results against budget
    public func validate(_ result: BenchmarkResult) -> ValidationResult {
        var violations: [BudgetViolation] = []
        var warnings: [BudgetWarning] = []
        
        for constraint in constraints {
            switch constraint.validate(result) {
            case .passed:
                continue
                
            case .warning(let message):
                warnings.append(BudgetWarning(
                    constraint: constraint.name,
                    message: message,
                    actual: constraint.extractValue(from: result),
                    threshold: constraint.threshold
                ))
                
            case .failed(let message):
                violations.append(BudgetViolation(
                    constraint: constraint.name,
                    message: message,
                    actual: constraint.extractValue(from: result),
                    threshold: constraint.threshold
                ))
            }
        }
        
        return ValidationResult(
            benchmark: result.name,
            violations: violations,
            warnings: warnings
        )
    }
    
    /// Validate suite results against budget
    public func validate(_ suite: BenchmarkSuiteResult) -> SuiteValidationResult {
        var results: [ValidationResult] = []
        
        for result in suite.results {
            results.append(validate(result))
        }
        
        return SuiteValidationResult(
            suite: suite.name,
            timestamp: suite.timestamp,
            results: results
        )
    }
}

// MARK: - Performance Constraints

public protocol PerformanceConstraint {
    var name: String { get }
    var threshold: Double { get }
    func validate(_ result: BenchmarkResult) -> ConstraintResult
    func extractValue(from result: BenchmarkResult) -> Double
}

public enum ConstraintResult {
    case passed
    case warning(String)
    case failed(String)
}

// MARK: - Built-in Constraints

public struct MaximumTimeConstraint: PerformanceConstraint {
    public let name: String
    public let threshold: Double
    public let metric: TimeMetric
    
    public init(name: String = "Maximum Time", threshold: Double, metric: TimeMetric = .mean) {
        self.name = name
        self.threshold = threshold
        self.metric = metric
    }
    
    public func validate(_ result: BenchmarkResult) -> ConstraintResult {
        let value = extractValue(from: result)
        
        if value <= threshold {
            return .passed
        } else if value <= threshold * 1.1 {
            return .warning("Performance near threshold: \(format(value)) > \(format(threshold))")
        } else {
            return .failed("Performance budget exceeded: \(format(value)) > \(format(threshold))")
        }
    }
    
    public func extractValue(from result: BenchmarkResult) -> Double {
        switch metric {
        case .mean:
            return result.statistics.mean
        case .median:
            return result.statistics.median
        case .percentile95:
            return result.statistics.percentile95
        case .max:
            return result.statistics.max
        }
    }
    
    private func format(_ value: Double) -> String {
        String(format: "%.3fms", value * 1000)
    }
    
    public enum TimeMetric {
        case mean
        case median
        case percentile95
        case max
    }
}

public struct MaximumMemoryConstraint: PerformanceConstraint {
    public let name: String
    public let threshold: Double // in bytes
    
    public init(name: String = "Maximum Memory", threshold: Double) {
        self.name = name
        self.threshold = threshold
    }
    
    public func validate(_ result: BenchmarkResult) -> ConstraintResult {
        let value = extractValue(from: result)
        
        if value <= threshold {
            return .passed
        } else if value <= threshold * 1.1 {
            return .warning("Memory usage near threshold: \(format(value)) > \(format(threshold))")
        } else {
            return .failed("Memory budget exceeded: \(format(value)) > \(format(threshold))")
        }
    }
    
    public func extractValue(from result: BenchmarkResult) -> Double {
        Double(result.memoryMeasurements.max() ?? 0)
    }
    
    private func format(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

public struct RegressionConstraint: PerformanceConstraint {
    public let name: String
    public let threshold: Double // percentage allowed regression
    public let baseline: BenchmarkResult
    
    public init(name: String = "Regression", threshold: Double = 10.0, baseline: BenchmarkResult) {
        self.name = name
        self.threshold = threshold
        self.baseline = baseline
    }
    
    public func validate(_ result: BenchmarkResult) -> ConstraintResult {
        let percentChange = extractValue(from: result)
        
        if percentChange <= threshold {
            return .passed
        } else if percentChange <= threshold * 1.5 {
            return .warning("Performance regression detected: \(String(format: "%.1f%%", percentChange))")
        } else {
            return .failed("Significant regression: \(String(format: "%.1f%%", percentChange)) > \(threshold)%")
        }
    }
    
    public func extractValue(from result: BenchmarkResult) -> Double {
        let current = result.statistics.mean
        let baseline = baseline.statistics.mean
        return ((current - baseline) / baseline) * 100
    }
}

// MARK: - Validation Results

public struct ValidationResult {
    public let benchmark: String
    public let violations: [BudgetViolation]
    public let warnings: [BudgetWarning]
    
    public var passed: Bool {
        violations.isEmpty
    }
    
    public var summary: String {
        if passed {
            if warnings.isEmpty {
                return "✅ \(benchmark): All performance budgets met"
            } else {
                return "⚠️ \(benchmark): Passed with \(warnings.count) warning(s)"
            }
        } else {
            return "❌ \(benchmark): \(violations.count) budget violation(s)"
        }
    }
    
    public var details: String {
        var lines: [String] = [summary]
        
        for violation in violations {
            lines.append("  ❌ \(violation.constraint): \(violation.message)")
        }
        
        for warning in warnings {
            lines.append("  ⚠️ \(warning.constraint): \(warning.message)")
        }
        
        return lines.joined(separator: "\n")
    }
}

public struct BudgetViolation {
    public let constraint: String
    public let message: String
    public let actual: Double
    public let threshold: Double
}

public struct BudgetWarning {
    public let constraint: String
    public let message: String
    public let actual: Double
    public let threshold: Double
}

public struct SuiteValidationResult {
    public let suite: String
    public let timestamp: Date
    public let results: [ValidationResult]
    
    public var passed: Bool {
        results.allSatisfy { $0.passed }
    }
    
    public var totalViolations: Int {
        results.reduce(0) { $0 + $1.violations.count }
    }
    
    public var totalWarnings: Int {
        results.reduce(0) { $0 + $1.warnings.count }
    }
    
    public var summary: String {
        """
        Performance Budget Validation
        =============================
        Suite: \(suite)
        Date: \(timestamp)
        
        Results:
        \(results.map { $0.details }.joined(separator: "\n\n"))
        
        Summary:
          Total Benchmarks: \(results.count)
          Passed: \(results.filter { $0.passed }.count)
          Failed: \(results.filter { !$0.passed }.count)
          Violations: \(totalViolations)
          Warnings: \(totalWarnings)
        
        Overall: \(passed ? "✅ PASSED" : "❌ FAILED")
        """
    }
    
    /// Generate CI-friendly output
    public func generateCIOutput() -> String {
        var output: [String] = []
        
        if !passed {
            output.append("::error::Performance budget validation failed")
        }
        
        for result in results where !result.passed {
            for violation in result.violations {
                output.append("::error file=\(result.benchmark)::\(violation.message)")
            }
        }
        
        for result in results {
            for warning in result.warnings {
                output.append("::warning file=\(result.benchmark)::\(warning.message)")
            }
        }
        
        return output.joined(separator: "\n")
    }
}

// MARK: - Constraint Builder

@resultBuilder
public struct ConstraintBuilder {
    public static func buildBlock(_ constraints: PerformanceConstraint...) -> [PerformanceConstraint] {
        constraints
    }
}

// MARK: - Default Budgets

public struct DefaultBudgets {
    
    /// Budget for app startup
    public static let startup = PerformanceBudget(name: "App Startup") {
        MaximumTimeConstraint(
            name: "Cold Start",
            threshold: 0.3, // 300ms
            metric: .percentile95
        )
        
        MaximumMemoryConstraint(
            name: "Initial Memory",
            threshold: 50 * 1024 * 1024 // 50MB
        )
    }
    
    /// Budget for view rendering
    public static let viewRendering = PerformanceBudget(name: "View Rendering") {
        MaximumTimeConstraint(
            name: "Frame Time",
            threshold: 0.016, // 16ms for 60fps
            metric: .percentile95
        )
        
        MaximumTimeConstraint(
            name: "Max Frame Time",
            threshold: 0.033, // 33ms absolute max
            metric: .max
        )
    }
    
    /// Budget for data operations
    public static let dataOperations = PerformanceBudget(name: "Data Operations") {
        MaximumTimeConstraint(
            name: "Fetch Time",
            threshold: 0.1, // 100ms
            metric: .mean
        )
        
        MaximumTimeConstraint(
            name: "Save Time",
            threshold: 0.05, // 50ms
            metric: .mean
        )
        
        MaximumMemoryConstraint(
            name: "Cache Size",
            threshold: 20 * 1024 * 1024 // 20MB
        )
    }
    
    /// Budget for network operations
    public static let networkOperations = PerformanceBudget(name: "Network Operations") {
        MaximumTimeConstraint(
            name: "API Response",
            threshold: 1.0, // 1 second
            metric: .percentile95
        )
        
        MaximumTimeConstraint(
            name: "Image Load",
            threshold: 2.0, // 2 seconds
            metric: .percentile95
        )
    }
}

// MARK: - CI Integration

public struct CIPerformanceEnforcer {
    
    /// Run benchmarks and enforce budgets for CI
    public static func enforce(
        suite: BenchmarkSuiteResult,
        budget: PerformanceBudget,
        failOnViolation: Bool = true
    ) -> Int32 {
        let validation = budget.validate(suite)
        
        print(validation.summary)
        
        if !validation.passed {
            print("\nCI Output:")
            print(validation.generateCIOutput())
            
            if failOnViolation {
                return 1 // Exit code for failure
            }
        }
        
        return 0 // Success
    }
    
    /// Compare against baseline and enforce regression limits
    public static func enforceRegression(
        current: BenchmarkSuiteResult,
        baseline: BenchmarkSuiteResult,
        maxRegressionPercent: Double = 10.0
    ) -> Int32 {
        let comparison = current.compare(to: baseline)
        
        print(comparison.summary)
        
        let regressions = comparison.comparisons.filter { $0.percentChange > maxRegressionPercent }
        
        if !regressions.isEmpty {
            print("\n❌ Performance regressions detected:")
            for regression in regressions {
                print("  - \(regression.name): \(String(format: "%+.1f%%", regression.percentChange))")
            }
            return 1
        }
        
        return 0
    }
}