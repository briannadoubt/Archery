import SwiftUI
import Archery

/// Interactive benchmarking view that demonstrates BenchmarkHarness
struct BenchmarksView: View {
    @State private var isRunning = false
    @State private var results: [BenchmarkResult] = []
    @State private var selectedBenchmark: BenchmarkType = .all

    enum BenchmarkType: String, CaseIterable, Sendable {
        case all = "All Benchmarks"
        case array = "Array Operations"
        case dictionary = "Dictionary Operations"
        case string = "String Operations"
        case container = "DI Container"
    }

    var body: some View {
        List {
            Section {
                Picker("Benchmark", selection: $selectedBenchmark) {
                    ForEach(BenchmarkType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                Button {
                    runBenchmarks()
                } label: {
                    HStack {
                        if isRunning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(isRunning ? "Running..." : "Run Benchmarks")
                    }
                }
                .disabled(isRunning)
            } header: {
                Label("Configuration", systemImage: "slider.horizontal.3")
            } footer: {
                Text("Runs 1000 iterations with 100 warmup iterations to ensure accurate measurements.")
            }

            if !results.isEmpty {
                Section {
                    ForEach(results, id: \.name) { result in
                        BenchmarkResultRow(result: result)
                    }
                } header: {
                    Label("Results", systemImage: "chart.bar")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        BenchmarkStatRow(label: "Total Benchmarks", value: "\(results.count)")
                        BenchmarkStatRow(label: "Fastest", value: formatTime(results.map(\.statistics.mean).min() ?? 0))
                        BenchmarkStatRow(label: "Slowest", value: formatTime(results.map(\.statistics.mean).max() ?? 0))
                    }
                } header: {
                    Label("Summary", systemImage: "info.circle")
                }
            }

            Section {
                Text("BenchmarkHarness provides microbenchmark capabilities with OS Signpost integration for profiling in Instruments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                BenchmarkCodeSnippetView("""
                let harness = BenchmarkHarness(
                    name: "MyBenchmark",
                    iterations: 1000
                )

                let result = harness.measure("Operation") {
                    // Code to benchmark
                }

                print(result.statistics.mean)
                """)
            } header: {
                Label("Usage", systemImage: "doc.text")
            }
        }
        .navigationTitle("Benchmarks")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    private func runBenchmarks() {
        isRunning = true
        results = []
        let benchmarkType = selectedBenchmark

        Task.detached(priority: .userInitiated) {
            let newResults = Self.executeBenchmarks(for: benchmarkType)

            await MainActor.run {
                results = newResults
                isRunning = false
            }
        }
    }

    private nonisolated static func executeBenchmarks(for type: BenchmarkType) -> [BenchmarkResult] {
        var newResults: [BenchmarkResult] = []
        let harness = BenchmarkHarness(name: "Showcase", iterations: 1000, warmupIterations: 100)

        switch type {
        case .all:
            newResults.append(runArrayBenchmark(harness))
            newResults.append(runDictionaryBenchmark(harness))
            newResults.append(runStringBenchmark(harness))
            newResults.append(runContainerBenchmark(harness))
        case .array:
            newResults.append(runArrayBenchmark(harness))
        case .dictionary:
            newResults.append(runDictionaryBenchmark(harness))
        case .string:
            newResults.append(runStringBenchmark(harness))
        case .container:
            newResults.append(runContainerBenchmark(harness))
        }

        return newResults
    }

    private nonisolated static func runArrayBenchmark(_ harness: BenchmarkHarness) -> BenchmarkResult {
        harness.measure("Array Append (1000 items)") {
            var array: [Int] = []
            array.reserveCapacity(1000)
            for i in 0..<1000 {
                array.append(i)
            }
        }
    }

    private nonisolated static func runDictionaryBenchmark(_ harness: BenchmarkHarness) -> BenchmarkResult {
        harness.measure("Dictionary Insert (1000 items)") {
            var dict: [String: Int] = [:]
            for i in 0..<1000 {
                dict["key\(i)"] = i
            }
        }
    }

    private nonisolated static func runStringBenchmark(_ harness: BenchmarkHarness) -> BenchmarkResult {
        harness.measure("String Concat (100 items)") {
            var result = ""
            for i in 0..<100 {
                result += "Item \(i) "
            }
        }
    }

    private nonisolated static func runContainerBenchmark(_ harness: BenchmarkHarness) -> BenchmarkResult {
        let container = EnvContainer()
        container.register("test-value")

        return harness.measure("Container Resolve (100 lookups)") {
            for _ in 0..<100 {
                _ = container.resolve() as String?
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        if seconds < 0.001 {
            return String(format: "%.2f µs", seconds * 1_000_000)
        } else {
            return String(format: "%.3f ms", seconds * 1000)
        }
    }
}

// MARK: - Supporting Views

private struct BenchmarkResultRow: View {
    let result: BenchmarkResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.name)
                .font(.headline)

            HStack(spacing: 16) {
                MetricView(label: "Mean", value: formatTime(result.statistics.mean))
                MetricView(label: "Min", value: formatTime(result.statistics.min))
                MetricView(label: "Max", value: formatTime(result.statistics.max))
            }

            // Visual bar showing relative performance
            GeometryReader { geo in
                let normalized = min(result.statistics.mean / 0.01, 1.0) // Normalize to 10ms max
                RoundedRectangle(cornerRadius: 4)
                    .fill(barColor(for: result.statistics.mean))
                    .frame(width: geo.size.width * normalized)
            }
            .frame(height: 8)
        }
        .padding(.vertical, 4)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        if seconds < 0.001 {
            return String(format: "%.1fµs", seconds * 1_000_000)
        } else {
            return String(format: "%.2fms", seconds * 1000)
        }
    }

    private func barColor(for time: TimeInterval) -> Color {
        if time < 0.001 { return .green }
        if time < 0.005 { return .yellow }
        return .orange
    }
}

private struct MetricView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .fontDesign(.monospaced)
        }
    }
}

private struct BenchmarkStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontDesign(.monospaced)
        }
    }
}

private struct BenchmarkCodeSnippetView: View {
    let code: String

    init(_ code: String) {
        self.code = code
    }

    var body: some View {
        Text(code)
            .font(.system(.caption, design: .monospaced))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    NavigationStack {
        BenchmarksView()
    }
}
