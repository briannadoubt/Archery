import Foundation

#if os(macOS) || os(Linux)

// MARK: - CI Integration and Performance Monitoring

public final class CIIntegration {
    private let configuration: CIConfiguration
    private let performanceMonitor: PerformanceMonitor
    private let cacheManager: CICacheManager
    
    public init(
        configuration: CIConfiguration = .default
    ) {
        self.configuration = configuration
        self.performanceMonitor = PerformanceMonitor(budgets: configuration.budgets)
        self.cacheManager = CICacheManager(configuration: configuration.cache)
    }
    
    // MARK: - Build Execution
    
    public func executeBuild() async throws -> BuildResult {
        let startTime = Date()
        var metrics = BuildMetrics()
        
        // Restore cache
        if configuration.cache.enabled {
            let cacheHits = await cacheManager.restoreCache()
            metrics.cacheHitRate = Double(cacheHits.count) / Double(configuration.cache.keys.count)
        }
        
        // Run build
        let buildOutput = try await runBuild()
        metrics.buildTime = Date().timeIntervalSince(startTime)
        
        // Measure binary size
        if let binaryPath = buildOutput.binaryPath {
            metrics.binarySize = try measureBinarySize(at: binaryPath)
            metrics.symbolCount = try countSymbols(at: binaryPath)
        }
        
        // Save cache
        if configuration.cache.enabled {
            await cacheManager.saveCache()
        }
        
        // Check budgets
        let budgetResults = performanceMonitor.checkBudgets(metrics)
        
        // Generate report
        let report = generateReport(
            metrics: metrics,
            budgetResults: budgetResults,
            buildOutput: buildOutput
        )
        
        return BuildResult(
            success: budgetResults.allPassed,
            metrics: metrics,
            budgetResults: budgetResults,
            report: report
        )
    }
    
    private func runBuild() async throws -> BuildOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["build"] + configuration.buildFlags
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        guard process.terminationStatus == 0 else {
            throw CIError.buildFailed(output)
        }
        
        // Parse build output
        let binaryPath = parseBinaryPath(from: output)
        
        return BuildOutput(
            output: output,
            binaryPath: binaryPath,
            exitCode: process.terminationStatus
        )
    }
    
    private func measureBinarySize(at path: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        return attributes[.size] as? Int ?? 0
    }
    
    private func countSymbols(at path: URL) throws -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nm")
        process.arguments = ["-g", path.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        return output.components(separatedBy: .newlines).count
    }
    
    private func parseBinaryPath(from output: String) -> URL? {
        // Parse binary path from build output
        // This would need actual implementation based on Swift build output format
        return nil
    }
    
    private func generateReport(
        metrics: BuildMetrics,
        budgetResults: BudgetCheckResults,
        buildOutput: BuildOutput
    ) -> String {
        """
        ========================================
        Archery CI Build Report
        ========================================
        
        Build Metrics:
        --------------
        Build Time: \(String(format: "%.2f", metrics.buildTime))s
        Binary Size: \(formatBytes(metrics.binarySize))
        Symbol Count: \(metrics.symbolCount)
        Cache Hit Rate: \(String(format: "%.1f%%", metrics.cacheHitRate * 100))
        
        Performance Budgets:
        --------------------
        \(budgetResults.summary)
        
        \(budgetResults.allPassed ? "✅ All budgets passed" : "❌ Some budgets failed")
        
        ========================================
        """
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Performance Monitor

public final class PerformanceMonitor {
    private let budgets: PerformanceBudgets
    private var measurements: [PerformanceMeasurement] = []
    
    init(budgets: PerformanceBudgets) {
        self.budgets = budgets
    }
    
    public func checkBudgets(_ metrics: BuildMetrics) -> BudgetCheckResults {
        var results = BudgetCheckResults()
        
        // Check build time
        if metrics.buildTime > budgets.buildTime {
            results.violations.append(BudgetViolation(
                constraint: "buildTime",
                message: "Build time exceeded budget",
                actual: metrics.buildTime,
                threshold: budgets.buildTime
            ))
        }

        // Check binary size
        if metrics.binarySize > budgets.binarySize {
            results.violations.append(BudgetViolation(
                constraint: "binarySize",
                message: "Binary size exceeded budget",
                actual: Double(metrics.binarySize),
                threshold: Double(budgets.binarySize)
            ))
        }

        // Check symbol count
        if metrics.symbolCount > budgets.symbolCount {
            results.violations.append(BudgetViolation(
                constraint: "symbolCount",
                message: "Symbol count exceeded budget",
                actual: Double(metrics.symbolCount),
                threshold: Double(budgets.symbolCount)
            ))
        }
        
        // Store measurement for trends
        measurements.append(PerformanceMeasurement(
            timestamp: Date(),
            metrics: metrics
        ))
        
        return results
    }
    
    public func generateTrendReport() -> TrendReport {
        guard measurements.count >= 2 else {
            return TrendReport(trends: [:])
        }
        
        var trends: [String: TrendInfo] = [:]
        
        // Calculate trends
        let recent = measurements.suffix(10)
        if recent.count >= 2 {
            let first = recent.first!
            let last = recent.last!
            
            trends["buildTime"] = TrendInfo(
                direction: last.metrics.buildTime > first.metrics.buildTime ? .increasing : .decreasing,
                percentChange: ((last.metrics.buildTime - first.metrics.buildTime) / first.metrics.buildTime) * 100
            )
            
            trends["binarySize"] = TrendInfo(
                direction: last.metrics.binarySize > first.metrics.binarySize ? .increasing : .decreasing,
                percentChange: Double((last.metrics.binarySize - first.metrics.binarySize)) / Double(first.metrics.binarySize) * 100
            )
        }
        
        return TrendReport(trends: trends)
    }
}

// MARK: - CI Cache Manager

public final class CICacheManager {
    private let configuration: CacheConfiguration
    private let cacheDirectory: URL
    
    init(configuration: CacheConfiguration) {
        self.configuration = configuration
        self.cacheDirectory = configuration.directory
    }
    
    public func restoreCache() async -> [String] {
        var restored: [String] = []
        
        for key in configuration.keys {
            if let cachedData = await fetchFromCache(key: key) {
                await restoreToLocation(data: cachedData, key: key)
                restored.append(key)
            }
        }
        
        return restored
    }
    
    public func saveCache() async {
        for key in configuration.keys {
            if let data = await collectCacheData(for: key) {
                await storeInCache(data: data, key: key)
            }
        }
    }
    
    private func fetchFromCache(key: String) async -> Data? {
        let cacheFile = cacheDirectory.appendingPathComponent("\(key).cache")
        return try? Data(contentsOf: cacheFile)
    }
    
    private func storeInCache(data: Data, key: String) async {
        let cacheFile = cacheDirectory.appendingPathComponent("\(key).cache")
        try? data.write(to: cacheFile)
    }
    
    private func restoreToLocation(data: Data, key: String) async {
        // Implementation depends on cache key type
        // This would restore build artifacts, dependencies, etc.
    }
    
    private func collectCacheData(for key: String) async -> Data? {
        // Implementation depends on cache key type
        // This would collect build artifacts, dependencies, etc.
        return nil
    }
}

// MARK: - GitHub Actions Generator

public struct GitHubActionsGenerator {
    public static func generateWorkflow(
        configuration: CIConfiguration
    ) -> String {
        """
        name: Archery CI
        
        on:
          push:
            branches: [ main, develop ]
          pull_request:
            branches: [ main ]
        
        env:
          CACHE_VERSION: v1
        
        jobs:
          lint:
            name: Lint
            runs-on: macos-latest
            steps:
              - uses: actions/checkout@v3
              
              - name: Cache SPM
                uses: actions/cache@v3
                with:
                  path: |
                    .build
                    ~/Library/Caches/org.swift.swiftpm
                  key: ${{ runner.os }}-spm-${{ hashFiles('Package.resolved') }}
                  restore-keys: |
                    ${{ runner.os }}-spm-
              
              - name: Run Module Linter
                run: |
                  swift run archery-lint \\
                    --project-root . \\
                    --format github
              
              - name: Check Performance Budgets
                run: |
                  swift run archery-perf \\
                    --check-budgets \\
                    --fail-on-violation
        
          build:
            name: Build and Test
            runs-on: macos-latest
            strategy:
              matrix:
                platform: [iOS, macOS, tvOS, watchOS, visionOS]
            
            steps:
              - uses: actions/checkout@v3
              
              - name: Select Xcode
                run: sudo xcode-select -s /Applications/Xcode_15.0.app
              
              - name: Cache Build
                uses: actions/cache@v3
                with:
                  path: |
                    .build
                    DerivedData
                  key: ${{ runner.os }}-build-${{ matrix.platform }}-${{ github.sha }}
                  restore-keys: |
                    ${{ runner.os }}-build-${{ matrix.platform }}-
              
              - name: Build
                run: |
                  swift build \\
                    --configuration release \\
                    --arch arm64 \\
                    --arch x86_64
              
              - name: Run Tests
                run: |
                  swift test \\
                    --configuration release \\
                    --parallel
              
              - name: Measure Performance
                run: |
                  swift run archery-benchmark \\
                    --output-format json \\
                    --output benchmark-results.json
              
              - name: Upload Benchmark Results
                uses: actions/upload-artifact@v3
                with:
                  name: benchmark-${{ matrix.platform }}
                  path: benchmark-results.json
        
          performance:
            name: Performance Analysis
            needs: build
            runs-on: macos-latest
            steps:
              - uses: actions/checkout@v3
              
              - name: Download Benchmarks
                uses: actions/download-artifact@v3
                with:
                  path: benchmarks
              
              - name: Analyze Performance
                run: |
                  swift run archery-analyze \\
                    --benchmarks benchmarks/ \\
                    --compare-with main \\
                    --fail-on-regression
              
              - name: Post Comment
                if: github.event_name == 'pull_request'
                uses: actions/github-script@v6
                with:
                  script: |
                    const fs = require('fs');
                    const report = fs.readFileSync('performance-report.md', 'utf8');
                    github.rest.issues.createComment({
                      issue_number: context.issue.number,
                      owner: context.repo.owner,
                      repo: context.repo.repo,
                      body: report
                    });
        """
    }
}

// MARK: - Configuration Types

public struct CIConfiguration: Codable, Sendable {
    public let buildFlags: [String]
    public let testFlags: [String]
    public let platforms: [Platform]
    public let budgets: PerformanceBudgets
    public let cache: CacheConfiguration
    
    public static let `default` = CIConfiguration(
        buildFlags: ["--configuration", "release"],
        testFlags: ["--parallel"],
        platforms: Platform.all,
        budgets: .default,
        cache: .default
    )
}

public struct CacheConfiguration: Codable, Sendable {
    public let enabled: Bool
    public let directory: URL
    public let keys: [String]
    public let maxSize: Int // bytes
    public let ttl: TimeInterval
    
    public static let `default` = CacheConfiguration(
        enabled: true,
        directory: URL(fileURLWithPath: "/tmp/archery-cache"),
        keys: ["spm", "build", "deriveddata"],
        maxSize: 1_000_000_000, // 1 GB
        ttl: 86400 // 24 hours
    )
}

// MARK: - Result Types

public struct BuildResult {
    public let success: Bool
    public let metrics: BuildMetrics
    public let budgetResults: BudgetCheckResults
    public let report: String
}

public struct BuildMetrics {
    public var buildTime: TimeInterval = 0
    public var binarySize: Int = 0
    public var symbolCount: Int = 0
    public var cacheHitRate: Double = 0
}

public struct BudgetCheckResults: Sendable {
    public var violations: [BudgetViolation] = []
    
    public var allPassed: Bool {
        violations.isEmpty
    }
    
    public var summary: String {
        if allPassed {
            return "All performance budgets met"
        } else {
            return violations.map { violation in
                "❌ \(violation.constraint): \(violation.message) - actual=\(violation.actual), threshold=\(violation.threshold)"
            }.joined(separator: "\n")
        }
    }
}

// BudgetViolation is defined in Benchmarking/PerformanceBudget.swift
// PerformanceMetric is defined in BuildConfiguration.swift

struct BuildOutput {
    let output: String
    let binaryPath: URL?
    let exitCode: Int32
}

struct PerformanceMeasurement {
    let timestamp: Date
    let metrics: BuildMetrics
}

public struct TrendReport {
    public let trends: [String: TrendInfo]
}

public struct TrendInfo {
    public enum Direction {
        case increasing, decreasing, stable
    }
    
    public let direction: Direction
    public let percentChange: Double
}

// MARK: - Errors

public enum CIError: LocalizedError {
    case buildFailed(String)
    case budgetExceeded(BudgetCheckResults)
    case cacheError(String)
    
    public var errorDescription: String? {
        switch self {
        case .buildFailed(let output):
            return "Build failed: \(output)"
        case .budgetExceeded(let results):
            return "Performance budgets exceeded: \(results.summary)"
        case .cacheError(let message):
            return "Cache error: \(message)"
        }
    }
}

#endif // os(macOS) || os(Linux)