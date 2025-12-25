import Foundation

/// Archery performance budget checker - validates build metrics against budgets
@main
struct ArcheryBudget {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())

        var configPath: String?
        var binaryPath: String?
        var buildTime: Double?
        var format: OutputFormat = .text
        var warnOnly = false

        // Parse arguments
        var i = 0
        while i < arguments.count {
            switch arguments[i] {
            case "--config", "-c":
                i += 1
                if i < arguments.count {
                    configPath = arguments[i]
                }
            case "--binary", "-b":
                i += 1
                if i < arguments.count {
                    binaryPath = arguments[i]
                }
            case "--build-time", "-t":
                i += 1
                if i < arguments.count {
                    buildTime = Double(arguments[i])
                }
            case "--format", "-f":
                i += 1
                if i < arguments.count {
                    format = OutputFormat(rawValue: arguments[i]) ?? .text
                }
            case "--warn-only":
                warnOnly = true
            case "--help", "-h":
                printUsage()
                return
            default:
                break
            }
            i += 1
        }

        let budgets = try loadBudgets(from: configPath)
        var results = BudgetResults()

        // Check binary size if path provided
        if let path = binaryPath {
            let size = try measureBinarySize(at: path)
            results.binarySize = size
            results.binarySizeStatus = checkBudget(
                value: Double(size),
                limit: Double(budgets.binarySize),
                name: "Binary Size"
            )
        }

        // Check build time if provided
        if let time = buildTime {
            results.buildTime = time
            results.buildTimeStatus = checkBudget(
                value: time,
                limit: budgets.buildTime,
                name: "Build Time"
            )
        }

        // Output results
        switch format {
        case .text:
            printTextResults(results, budgets: budgets)
        case .json:
            printJSONResults(results, budgets: budgets)
        case .github:
            printGitHubResults(results, budgets: budgets)
        }

        // Exit with error if budget exceeded
        if !warnOnly && results.hasFailures {
            exit(1)
        }
    }

    static func printUsage() {
        print("""
        Usage: archery-budget [options]

        Options:
          -c, --config <path>       Budget configuration file
          -b, --binary <path>       Path to binary to measure size
          -t, --build-time <secs>   Build time in seconds
          -f, --format <format>     Output format: text, json, github (default: text)
          --warn-only               Don't fail on budget violations
          -h, --help                Show this help

        Example:
          archery-budget --binary .build/release/MyApp --build-time 45.2
          archery-budget --config budgets.json --format github
        """)
    }

    static func loadBudgets(from path: String?) throws -> PerformanceBudgets {
        guard let path = path else {
            return .default
        }

        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PerformanceBudgets.self, from: data)
    }

    static func measureBinarySize(at path: String) throws -> Int {
        let url = URL(fileURLWithPath: path)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int ?? 0
    }

    static func checkBudget(value: Double, limit: Double, name: String) -> BudgetStatus {
        if value <= limit {
            return .passed
        } else if value <= limit * 1.1 {
            return .warning(exceeded: value - limit)
        } else {
            return .failed(exceeded: value - limit)
        }
    }

    static func printTextResults(_ results: BudgetResults, budgets: PerformanceBudgets) {
        print("\n" + String(repeating: "=", count: 50))
        print("Archery Performance Budget Check")
        print(String(repeating: "=", count: 50) + "\n")

        if let size = results.binarySize {
            let icon = results.binarySizeStatus?.icon ?? "⏳"
            print("\(icon) Binary Size: \(formatBytes(size)) / \(formatBytes(budgets.binarySize))")
            if case .failed(let exceeded) = results.binarySizeStatus {
                print("   Exceeded by: \(formatBytes(Int(exceeded)))")
            }
        }

        if let time = results.buildTime {
            let icon = results.buildTimeStatus?.icon ?? "⏳"
            print("\(icon) Build Time: \(String(format: "%.1f", time))s / \(String(format: "%.1f", budgets.buildTime))s")
            if case .failed(let exceeded) = results.buildTimeStatus {
                print("   Exceeded by: \(String(format: "%.1f", exceeded))s")
            }
        }

        print("\n" + String(repeating: "-", count: 50))

        if results.hasFailures {
            print("❌ Budget check FAILED")
        } else if results.hasWarnings {
            print("⚠️ Budget check passed with warnings")
        } else {
            print("✅ All budgets passed!")
        }

        print(String(repeating: "=", count: 50) + "\n")
    }

    static func printJSONResults(_ results: BudgetResults, budgets: PerformanceBudgets) {
        struct JSONOutput: Encodable {
            let binarySize: BinarySizeOutput?
            let buildTime: BuildTimeOutput?
            let passed: Bool
            let hasWarnings: Bool

            struct BinarySizeOutput: Encodable {
                let value: Int
                let limit: Int
                let status: String
            }

            struct BuildTimeOutput: Encodable {
                let value: Double
                let limit: Double
                let status: String
            }
        }

        let output = JSONOutput(
            binarySize: results.binarySize.map {
                JSONOutput.BinarySizeOutput(
                    value: $0,
                    limit: budgets.binarySize,
                    status: results.binarySizeStatus?.rawValue ?? "unknown"
                )
            },
            buildTime: results.buildTime.map {
                JSONOutput.BuildTimeOutput(
                    value: $0,
                    limit: budgets.buildTime,
                    status: results.buildTimeStatus?.rawValue ?? "unknown"
                )
            },
            passed: !results.hasFailures,
            hasWarnings: results.hasWarnings
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(output),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }

    static func printGitHubResults(_ results: BudgetResults, budgets: PerformanceBudgets) {
        if let size = results.binarySize {
            switch results.binarySizeStatus {
            case .passed:
                print("::notice::Binary size: \(formatBytes(size)) (limit: \(formatBytes(budgets.binarySize)))")
            case .warning(let exceeded):
                print("::warning::Binary size approaching limit: \(formatBytes(size)) (limit: \(formatBytes(budgets.binarySize)), +\(formatBytes(Int(exceeded))))")
            case .failed(let exceeded):
                print("::error::Binary size exceeded: \(formatBytes(size)) (limit: \(formatBytes(budgets.binarySize)), +\(formatBytes(Int(exceeded))))")
            case nil:
                break
            }
        }

        if let time = results.buildTime {
            switch results.buildTimeStatus {
            case .passed:
                print("::notice::Build time: \(String(format: "%.1f", time))s (limit: \(String(format: "%.1f", budgets.buildTime))s)")
            case .warning(let exceeded):
                print("::warning::Build time approaching limit: \(String(format: "%.1f", time))s (+\(String(format: "%.1f", exceeded))s)")
            case .failed(let exceeded):
                print("::error::Build time exceeded: \(String(format: "%.1f", time))s (+\(String(format: "%.1f", exceeded))s)")
            case nil:
                break
            }
        }

        if results.hasFailures {
            print("::error::Performance budget check failed")
        }
    }

    static func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

enum OutputFormat: String {
    case text
    case json
    case github
}

// MARK: - Budgets

struct PerformanceBudgets: Codable {
    var buildTime: TimeInterval      // seconds
    var binarySize: Int              // bytes
    var testTime: TimeInterval       // seconds
    var memoryUsage: Int             // bytes

    static let `default` = PerformanceBudgets(
        buildTime: 120,              // 2 minutes
        binarySize: 50_000_000,      // 50 MB
        testTime: 300,               // 5 minutes
        memoryUsage: 150_000_000     // 150 MB
    )

    static let strict = PerformanceBudgets(
        buildTime: 60,               // 1 minute
        binarySize: 30_000_000,      // 30 MB
        testTime: 180,               // 3 minutes
        memoryUsage: 100_000_000     // 100 MB
    )
}

// MARK: - Results

struct BudgetResults {
    var binarySize: Int?
    var binarySizeStatus: BudgetStatus?
    var buildTime: Double?
    var buildTimeStatus: BudgetStatus?

    var hasFailures: Bool {
        [binarySizeStatus, buildTimeStatus].contains { status in
            if case .failed = status { return true }
            return false
        }
    }

    var hasWarnings: Bool {
        [binarySizeStatus, buildTimeStatus].contains { status in
            if case .warning = status { return true }
            return false
        }
    }
}

enum BudgetStatus {
    case passed
    case warning(exceeded: Double)
    case failed(exceeded: Double)

    var rawValue: String {
        switch self {
        case .passed: return "passed"
        case .warning: return "warning"
        case .failed: return "failed"
        }
    }

    var icon: String {
        switch self {
        case .passed: return "✅"
        case .warning: return "⚠️"
        case .failed: return "❌"
        }
    }
}
