import SwiftUI
import Archery

// MARK: - Benchmarking Example App

@main
struct BenchmarkingExampleApp: App {
    var body: some Scene {
        WindowGroup {
            BenchmarkingView()
        }
    }
}

// MARK: - Main View

struct BenchmarkingView: View {
    @StateObject private var runner = BenchmarkRunner()
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            MicrobenchmarkView(runner: runner)
                .tabItem {
                    Label("Microbenchmarks", systemImage: "speedometer")
                }
                .tag(0)
            
            PerformanceBudgetView(runner: runner)
                .tabItem {
                    Label("Budgets", systemImage: "gauge")
                }
                .tag(1)
            
            SnapshotComparisonView(runner: runner)
                .tabItem {
                    Label("Snapshots", systemImage: "camera")
                }
                .tag(2)
            
            InstrumentsView(runner: runner)
                .tabItem {
                    Label("Instruments", systemImage: "waveform.path.ecg")
                }
                .tag(3)
        }
        .environmentObject(runner)
    }
}

// MARK: - Microbenchmark View

struct MicrobenchmarkView: View {
    @ObservedObject var runner: BenchmarkRunner
    @State private var isRunning = false
    @State private var selectedBenchmark = "All"
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Benchmark Selection
                Picker("Benchmark", selection: $selectedBenchmark) {
                    Text("All Benchmarks").tag("All")
                    Text("Container Lookup").tag("Container")
                    Text("Repository Caching").tag("Repository")
                    Text("View Rendering").tag("Rendering")
                    Text("State Machine").tag("StateMachine")
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Run Button
                Button(action: runBenchmarks) {
                    HStack {
                        if isRunning {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        }
                        Text(isRunning ? "Running..." : "Run Benchmarks")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isRunning)
                .padding(.horizontal)
                
                // Results
                if let results = runner.latestResults {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 15) {
                            ForEach(results, id: \.name) { result in
                                BenchmarkResultCard(result: result)
                            }
                        }
                        .padding()
                    }
                } else {
                    Spacer()
                    Text("No results yet")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .navigationTitle("Microbenchmarks")
        }
    }
    
    func runBenchmarks() {
        Task {
            isRunning = true
            await runner.runBenchmarks(filter: selectedBenchmark)
            isRunning = false
        }
    }
}

struct BenchmarkResultCard: View {
    let result: BenchmarkResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(result.name)
                .font(.headline)
            
            HStack {
                StatView(label: "Mean", value: formatTime(result.statistics.mean))
                Spacer()
                StatView(label: "Median", value: formatTime(result.statistics.median))
                Spacer()
                StatView(label: "95%ile", value: formatTime(result.statistics.percentile95))
            }
            
            HStack {
                StatView(label: "Min", value: formatTime(result.statistics.min))
                Spacer()
                StatView(label: "Max", value: formatTime(result.statistics.max))
                Spacer()
                StatView(label: "StdDev", value: formatTime(result.statistics.standardDeviation))
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        String(format: "%.3fms", time * 1000)
    }
}

struct StatView: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

// MARK: - Performance Budget View

struct PerformanceBudgetView: View {
    @ObservedObject var runner: BenchmarkRunner
    @State private var isValidating = false
    @State private var validationResults: [ValidationResult] = []
    @State private var selectedBudget = "Startup"
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Budget Selection
                Picker("Budget", selection: $selectedBudget) {
                    Text("App Startup").tag("Startup")
                    Text("View Rendering").tag("Rendering")
                    Text("Data Operations").tag("Data")
                    Text("Network").tag("Network")
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Validate Button
                Button(action: validateBudget) {
                    HStack {
                        if isValidating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        }
                        Text(isValidating ? "Validating..." : "Validate Budget")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isValidating)
                .padding(.horizontal)
                
                // Validation Results
                if !validationResults.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 15) {
                            ForEach(validationResults, id: \.benchmark) { result in
                                ValidationResultCard(result: result)
                            }
                        }
                        .padding()
                    }
                } else {
                    Spacer()
                    Text("No validation results")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .navigationTitle("Performance Budgets")
        }
    }
    
    func validateBudget() {
        Task {
            isValidating = true
            validationResults = await runner.validateBudget(selectedBudget)
            isValidating = false
        }
    }
}

struct ValidationResultCard: View {
    let result: ValidationResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.passed ? .green : .red)
                Text(result.benchmark)
                    .font(.headline)
            }
            
            if !result.violations.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Violations:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(result.violations, id: \.constraint) { violation in
                        Text("• \(violation.constraint): \(violation.message)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            if !result.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Warnings:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(result.warnings, id: \.constraint) { warning in
                        Text("• \(warning.constraint): \(warning.message)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Snapshot Comparison View

struct SnapshotComparisonView: View {
    @ObservedObject var runner: BenchmarkRunner
    @State private var isComparing = false
    @State private var comparison: SnapshotComparison?
    @State private var selectedVersions = (current: "1.1.0", baseline: "1.0.0")
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Version Selection
                HStack {
                    VStack(alignment: .leading) {
                        Text("Current")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Version", text: $selectedVersions.current)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading) {
                        Text("Baseline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Version", text: $selectedVersions.baseline)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                .padding()
                
                // Compare Button
                Button(action: compareSnapshots) {
                    HStack {
                        if isComparing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        }
                        Text(isComparing ? "Comparing..." : "Compare Snapshots")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isComparing)
                .padding(.horizontal)
                
                // Comparison Results
                if let comparison = comparison {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 15) {
                            // Overall Summary
                            HStack {
                                Text("Overall Speedup:")
                                    .font(.headline)
                                Spacer()
                                Text(String(format: "%.2fx", comparison.overallSpeedup))
                                    .font(.system(.title2, design: .monospaced))
                                    .foregroundColor(comparison.overallSpeedup > 1.05 ? .green :
                                                   comparison.overallSpeedup < 0.95 ? .red : .primary)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                            
                            // Improvements
                            if !comparison.improvements.isEmpty {
                                VStack(alignment: .leading) {
                                    Text("🚀 Improvements")
                                        .font(.headline)
                                    ForEach(comparison.improvements, id: \.current.name) { comp in
                                        ComparisonCard(comparison: comp)
                                    }
                                }
                            }
                            
                            // Regressions
                            if !comparison.regressions.isEmpty {
                                VStack(alignment: .leading) {
                                    Text("🐌 Regressions")
                                        .font(.headline)
                                    ForEach(comparison.regressions, id: \.current.name) { comp in
                                        ComparisonCard(comparison: comp)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                } else {
                    Spacer()
                    Text("No comparison results")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .navigationTitle("Snapshot Comparison")
        }
    }
    
    func compareSnapshots() {
        Task {
            isComparing = true
            comparison = await runner.compareSnapshots(
                current: selectedVersions.current,
                baseline: selectedVersions.baseline
            )
            isComparing = false
        }
    }
}

struct ComparisonCard: View {
    let comparison: BenchmarkSnapshotComparison
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(comparison.current.name)
                .font(.subheadline)
            
            HStack {
                Text(String(format: "%.3fms", comparison.baseline.metrics.mean * 1000))
                    .font(.system(.caption, design: .monospaced))
                Image(systemName: "arrow.right")
                    .font(.caption)
                Text(String(format: "%.3fms", comparison.current.metrics.mean * 1000))
                    .font(.system(.caption, design: .monospaced))
                Spacer()
                Text(String(format: "%+.1f%%", comparison.percentChange))
                    .font(.caption)
                    .foregroundColor(comparison.speedup > 1.05 ? .green :
                                   comparison.speedup < 0.95 ? .red : .primary)
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Instruments View

struct InstrumentsView: View {
    @ObservedObject var runner: BenchmarkRunner
    @State private var selectedTemplate = "Startup"
    @State private var isExporting = false
    @State private var exportPath = ""
    @State private var showingExportAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Template Selection
                Picker("Template", selection: $selectedTemplate) {
                    Text("App Startup").tag("Startup")
                    Text("UI Performance").tag("UI")
                    Text("Memory").tag("Memory")
                    Text("Network").tag("Network")
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Template Info
                TemplateInfoCard(template: selectedTemplate)
                
                // Export Button
                Button(action: exportTemplate) {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        }
                        Text(isExporting ? "Exporting..." : "Export Template")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isExporting)
                .padding(.horizontal)
                
                // Signpost Demo
                VStack(alignment: .leading, spacing: 10) {
                    Text("Signpost Demo")
                        .font(.headline)
                    
                    Button("Trigger App Launch Signpost") {
                        runner.triggerSignpost(.appLaunch)
                    }
                    
                    Button("Trigger Data Fetch Signpost") {
                        runner.triggerSignpost(.dataFetch)
                    }
                    
                    Button("Trigger Custom Signpost") {
                        runner.triggerSignpost(.custom("Demo Operation"))
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Instruments Integration")
            .alert("Template Exported", isPresented: $showingExportAlert) {
                Button("OK") { }
            } message: {
                Text("Template exported to: \(exportPath)")
            }
        }
    }
    
    func exportTemplate() {
        Task {
            isExporting = true
            exportPath = await runner.exportInstrumentsTemplate(selectedTemplate)
            isExporting = false
            showingExportAlert = true
        }
    }
}

struct TemplateInfoCard: View {
    let template: String
    
    var templateInfo: (name: String, instruments: [String]) {
        switch template {
        case "Startup":
            return ("App Startup", ["Time Profiler", "System Trace", "Allocations"])
        case "UI":
            return ("UI Performance", ["SwiftUI Profiler", "Time Profiler", "Hang Detection", "System Trace"])
        case "Memory":
            return ("Memory", ["Allocations", "Leaks"])
        case "Network":
            return ("Network", ["Network Activity", "Time Profiler"])
        default:
            return ("Unknown", [])
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(templateInfo.name)
                .font(.headline)
            
            Text("Included Instruments:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            ForEach(templateInfo.instruments, id: \.self) { instrument in
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text(instrument)
                        .font(.caption)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}

// MARK: - Benchmark Runner

@MainActor
class BenchmarkRunner: ObservableObject {
    @Published var latestResults: [BenchmarkResult]?
    @Published var latestValidation: SuiteValidationResult?
    
    func runBenchmarks(filter: String) async {
        let harness = BenchmarkHarness(name: "Example")
        var results: [BenchmarkResult] = []
        
        if filter == "All" || filter == "Container" {
            // Container benchmark
            var container = EnvContainer()
            for i in 0..<100 {
                container.register("service\(i)", factory: { MockService(id: i) })
            }
            
            let containerResult = harness.measure("Container Lookup") {
                for i in 0..<100 {
                    _ = container.resolve("service\(i)", as: MockService.self)
                }
            }
            results.append(containerResult)
        }
        
        if filter == "All" || filter == "Repository" {
            // Repository benchmark
            let repository = MockRepository()
            _ = try? await repository.fetchData(id: "test")
            
            let repoResult = await harness.measureAsync("Repository Cache Hit") {
                _ = try? await repository.fetchData(id: "test")
            }
            results.append(repoResult)
        }
        
        if filter == "All" || filter == "Rendering" {
            // View rendering benchmark
            let renderResult = harness.measure("View Rendering", iterations: 100) {
                _ = ComplexView()
                    .frame(width: 375, height: 812)
            }
            results.append(renderResult)
        }
        
        if filter == "All" || filter == "StateMachine" {
            // State machine benchmark
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
            
            let stateResult = harness.measure("State Machine Transitions", iterations: 1000) {
                var state = 0
                for _ in 0..<100 {
                    state = stateMachine.transition(state, .increment) ?? state
                    state = stateMachine.transition(state, .decrement) ?? state
                }
            }
            results.append(stateResult)
        }
        
        self.latestResults = results
    }
    
    func validateBudget(_ budgetType: String) async -> [ValidationResult] {
        guard let results = latestResults else {
            // Run benchmarks first
            await runBenchmarks(filter: "All")
            guard let results = latestResults else { return [] }
            return validateResults(results, budgetType: budgetType)
        }
        
        return validateResults(results, budgetType: budgetType)
    }
    
    private func validateResults(_ results: [BenchmarkResult], budgetType: String) -> [ValidationResult] {
        let budget: PerformanceBudget
        
        switch budgetType {
        case "Startup":
            budget = DefaultBudgets.startup
        case "Rendering":
            budget = DefaultBudgets.viewRendering
        case "Data":
            budget = DefaultBudgets.dataOperations
        case "Network":
            budget = DefaultBudgets.networkOperations
        default:
            budget = DefaultBudgets.startup
        }
        
        return results.map { budget.validate($0) }
    }
    
    func compareSnapshots(current: String, baseline: String) async -> SnapshotComparison? {
        // Create mock snapshots for demo
        let currentVersion = parseVersion(current)
        let baselineVersion = parseVersion(baseline)
        
        // Run benchmarks if needed
        if latestResults == nil {
            await runBenchmarks(filter: "All")
        }
        
        guard let results = latestResults else { return nil }
        
        // Create snapshots from results
        let currentSnapshots = results.map { BenchmarkSnapshot(from: $0) }
        let baselineSnapshots = results.map { result in
            // Simulate baseline being 20% slower
            BenchmarkSnapshot(
                name: result.name,
                iterations: result.iterations,
                metrics: BenchmarkMetrics(
                    mean: result.statistics.mean * 1.2,
                    median: result.statistics.median * 1.2,
                    min: result.statistics.min * 1.2,
                    max: result.statistics.max * 1.2,
                    standardDeviation: result.statistics.standardDeviation,
                    percentile95: result.statistics.percentile95 * 1.2,
                    memoryPeak: Int64(result.memoryMeasurements.max() ?? 0)
                )
            )
        }
        
        let currentSnapshot = PerformanceSnapshot(
            version: currentVersion,
            benchmarks: currentSnapshots
        )
        
        let baselineSnapshot = PerformanceSnapshot(
            version: baselineVersion,
            benchmarks: baselineSnapshots
        )
        
        return currentSnapshot.compare(to: baselineSnapshot)
    }
    
    private func parseVersion(_ versionString: String) -> Version {
        let components = versionString.split(separator: ".").compactMap { Int($0) }
        return Version(
            major: components.indices.contains(0) ? components[0] : 0,
            minor: components.indices.contains(1) ? components[1] : 0,
            patch: components.indices.contains(2) ? components[2] : 0
        )
    }
    
    func exportInstrumentsTemplate(_ templateType: String) async -> String {
        let config: InstrumentsConfig
        
        switch templateType {
        case "Startup":
            config = DefaultInstrumentsTemplates.startup
        case "UI":
            config = DefaultInstrumentsTemplates.uiPerformance
        case "Memory":
            config = DefaultInstrumentsTemplates.memory
        case "Network":
            config = DefaultInstrumentsTemplates.network
        default:
            config = DefaultInstrumentsTemplates.startup
        }
        
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(templateType).tracetemplate")
        
        try? config.exportTemplate(to: url)
        
        return url.path
    }
    
    enum SignpostType {
        case appLaunch
        case dataFetch
        case custom(String)
    }
    
    func triggerSignpost(_ type: SignpostType) {
        Task {
            let interval: SignpostInterval
            
            switch type {
            case .appLaunch:
                interval = SignpostMarkers.appLaunch()
            case .dataFetch:
                interval = SignpostMarkers.dataFetch(source: "Demo")
            case .custom(let name):
                interval = SignpostMarkers.custom(name)
            }
            
            await interval.measure {
                // Simulate work
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
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

struct StateMachine<State, Action> {
    let initialState: State
    let transition: (State, Action) -> State?
    
    func transition(_ state: State, _ action: Action) -> State? {
        transition(state, action)
    }
}