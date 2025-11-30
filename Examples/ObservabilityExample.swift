import SwiftUI
import Archery

// MARK: - Example App

@main
struct ObservabilityExampleApp: App {
    @StateObject private var telemetryService = TelemetryService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(telemetryService)
                .task {
                    await telemetryService.initialize()
                }
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var telemetryService: TelemetryService
    @State private var showDashboard = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Tracing Examples") {
                    Button("Simple Operation") {
                        Task {
                            await performSimpleOperation()
                        }
                    }
                    
                    Button("Nested Operations") {
                        Task {
                            await performNestedOperations()
                        }
                    }
                    
                    Button("Operation with Error") {
                        Task {
                            await performOperationWithError()
                        }
                    }
                    
                    Button("Distributed Trace") {
                        Task {
                            await performDistributedTrace()
                        }
                    }
                }
                
                Section("Metrics Examples") {
                    Button("Record Counter") {
                        recordCounter()
                    }
                    
                    Button("Record Gauge") {
                        recordGauge()
                    }
                    
                    Button("Record Histogram") {
                        recordHistogram()
                    }
                    
                    Button("High Cardinality Metric") {
                        recordHighCardinalityMetric()
                    }
                }
                
                Section("Logging Examples") {
                    Button("Log Info") {
                        logInfo()
                    }
                    
                    Button("Log Warning") {
                        logWarning()
                    }
                    
                    Button("Log Error") {
                        logError()
                    }
                    
                    Button("Structured Log") {
                        logStructured()
                    }
                }
                
                Section("Breadcrumb Examples") {
                    Button("Navigation Breadcrumb") {
                        recordNavigationBreadcrumb()
                    }
                    
                    Button("UI Breadcrumb") {
                        recordUIBreadcrumb()
                    }
                    
                    Button("Network Breadcrumb") {
                        recordNetworkBreadcrumb()
                    }
                }
                
                Section("Dashboard") {
                    Button("Show Observability Dashboard") {
                        showDashboard = true
                    }
                }
            }
            .navigationTitle("Observability Examples")
            .sheet(isPresented: $showDashboard) {
                ObservabilityDashboard()
            }
        }
    }
    
    // MARK: - Tracing Operations
    
    @MainActor
    private func performSimpleOperation() async {
        let span = ContextPropagator.shared.startSpan(
            name: "simple.operation",
            attributes: ["operation.type": "example"]
        )
        
        defer {
            ContextPropagator.shared.endSpan(span)
        }
        
        span.setAttribute("user.id", value: "user123")
        span.addEvent("Starting operation")
        
        // Simulate work
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        span.addEvent("Operation completed")
        span.setStatus(.ok)
    }
    
    @MainActor
    private func performNestedOperations() async {
        let parentSpan = ContextPropagator.shared.startSpan(
            name: "parent.operation"
        )
        
        defer {
            ContextPropagator.shared.endSpan(parentSpan)
        }
        
        // Child operation 1
        let child1 = ContextPropagator.shared.startSpan(
            name: "child.operation.1"
        )
        try? await Task.sleep(nanoseconds: 50_000_000)
        child1.setStatus(.ok)
        ContextPropagator.shared.endSpan(child1)
        
        // Child operation 2
        let child2 = ContextPropagator.shared.startSpan(
            name: "child.operation.2"
        )
        try? await Task.sleep(nanoseconds: 75_000_000)
        child2.setStatus(.ok)
        ContextPropagator.shared.endSpan(child2)
        
        parentSpan.setStatus(.ok)
    }
    
    @MainActor
    private func performOperationWithError() async {
        let span = ContextPropagator.shared.startSpan(
            name: "error.operation"
        )
        
        defer {
            ContextPropagator.shared.endSpan(span)
        }
        
        span.addEvent("Starting risky operation")
        
        // Simulate error
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        let error = NSError(
            domain: "ExampleError",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: "Something went wrong"]
        )
        
        span.addEvent("Error occurred", attributes: [
            "error.type": "ExampleError",
            "error.code": 500
        ])
        span.setStatus(.error(error), message: "Operation failed")
    }
    
    @MainActor
    private func performDistributedTrace() async {
        let context = ContextPropagator.shared.startTrace()
        
        let span = ContextPropagator.shared.startSpan(
            name: "distributed.request"
        )
        
        defer {
            ContextPropagator.shared.endSpan(span)
        }
        
        // Inject context into headers for distributed tracing
        var headers = [String: String]()
        ContextPropagator.shared.injectIntoHeaders(&headers)
        
        span.setAttribute("http.method", value: "GET")
        span.setAttribute("http.url", value: "https://api.example.com/data")
        span.setAttribute("http.headers", value: headers.description)
        
        // Simulate network call
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        span.setAttribute("http.status_code", value: 200)
        span.setStatus(.ok)
    }
    
    // MARK: - Metrics Recording
    
    private func recordCounter() {
        let counter = Counter(
            name: "button.clicks",
            value: 1,
            attributes: [
                "button.name": "record_counter",
                "screen": "examples"
            ]
        )
        
        Task {
            await ObservabilityEngine.shared.recordMetric(counter)
        }
        
        Task {
            await BreadcrumbRecorder.shared.record(
                category: .ui,
                message: "Counter recorded",
                data: ["metric": "button.clicks"]
            )
        }
    }
    
    private func recordGauge() {
        let memoryUsage = Double.random(in: 50...200)
        let gauge = Gauge(
            name: "memory.usage",
            value: memoryUsage,
            unit: .bytes,
            attributes: [
                "process": "main",
                "type": "heap"
            ]
        )
        
        Task {
            await ObservabilityEngine.shared.recordMetric(gauge)
        }
    }
    
    private func recordHistogram() {
        let responseTime = Double.random(in: 0.01...2.0)
        let histogram = Histogram(
            name: "api.response_time",
            value: responseTime,
            unit: .seconds,
            attributes: [
                "endpoint": "/users",
                "method": "GET"
            ]
        )
        
        Task {
            await ObservabilityEngine.shared.recordMetric(histogram)
        }
    }
    
    private func recordHighCardinalityMetric() {
        // This will trigger cardinality guards
        for i in 0..<20 {
            let counter = Counter(
                name: "high.cardinality",
                value: 1,
                attributes: [
                    "unique_id": UUID().uuidString,
                    "index": "\(i)"
                ]
            )
            
            Task {
                await ObservabilityEngine.shared.recordMetric(counter)
            }
        }
    }
    
    // MARK: - Logging
    
    private func logInfo() {
        let log = LogEntry(
            level: .info,
            message: "This is an informational message",
            attributes: [
                "component": "example",
                "action": "log_info"
            ]
        )
        
        Task {
            await ObservabilityEngine.shared.recordLog(log)
        }
    }
    
    private func logWarning() {
        let log = LogEntry(
            level: .warning,
            message: "This is a warning about potential issues",
            attributes: [
                "component": "example",
                "threshold": "80%"
            ]
        )
        
        Task {
            await ObservabilityEngine.shared.recordLog(log)
        }
    }
    
    private func logError() {
        let exception = ExceptionInfo(
            type: "ValidationError",
            message: "Invalid input provided",
            stackTrace: [
                "ContentView.logError()",
                "Button.action()",
                "View.onTapGesture()"
            ]
        )
        
        let log = LogEntry(
            level: .error,
            message: "Validation failed for user input",
            attributes: [
                "component": "example",
                "field": "email"
            ],
            exception: exception
        )
        
        Task {
            await ObservabilityEngine.shared.recordLog(log)
        }
    }
    
    private func logStructured() {
        let log = LogEntry(
            level: .info,
            message: "User action completed",
            attributes: [
                "user_id": "user123",
                "action": "purchase",
                "product_id": "prod456",
                "amount": "99.99",
                "currency": "USD"
            ]
        )
        
        Task {
            await ObservabilityEngine.shared.recordLog(log)
        }
    }
    
    // MARK: - Breadcrumbs
    
    private func recordNavigationBreadcrumb() {
        Task {
            await BreadcrumbRecorder.shared.record(
                category: .navigation,
                message: "Navigated to dashboard",
                level: .info,
                data: [
                    "from": "examples",
                    "to": "dashboard"
                ]
            )
        }
    }
    
    private func recordUIBreadcrumb() {
        Task {
            await BreadcrumbRecorder.shared.record(
                category: .ui,
                message: "Button tapped",
                level: .debug,
                data: [
                    "button": "ui_breadcrumb",
                    "screen": "examples"
                ]
            )
        }
    }
    
    private func recordNetworkBreadcrumb() {
        Task {
            await BreadcrumbRecorder.shared.record(
                category: .network,
                message: "API request completed",
                level: .info,
                data: [
                    "endpoint": "/api/data",
                    "status": "200",
                    "duration": "125ms"
                ]
            )
        }
    }
}

// MARK: - Telemetry Service

@MainActor
class TelemetryService: ObservableObject {
    private var exporters: [any TelemetryExporter] = []
    private var samplers: [any TelemetrySampler] = []
    
    func initialize() async {
        // Setup console exporter for development
        let consoleExporter = ConsoleExporter(prettyPrint: true)
        await ObservabilityEngine.shared.addExporter(consoleExporter)
        
        // Setup file exporter
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        let telemetryDir = documentsPath.appendingPathComponent("telemetry")
        let fileExporter = FileExporter(directory: telemetryDir)
        await ObservabilityEngine.shared.addExporter(fileExporter)
        
        // Setup OpenTelemetry exporter (if endpoint available)
        if let endpoint = URL(string: "http://localhost:4318") {
            let otelExporter = OpenTelemetryExporter(
                endpoint: endpoint,
                headers: ["Authorization": "Bearer example-token"]
            )
            let batchExporter = BatchExporter(wrapped: otelExporter)
            await ObservabilityEngine.shared.addExporter(batchExporter)
        }
        
        // Setup samplers
        let probabilitySampler = ProbabilitySampler(probability: 0.1)
        await ObservabilityEngine.shared.addSampler(probabilitySampler)
        
        let errorSampler = ErrorBasedSampler(
            baselineProbability: 0.05,
            errorProbability: 1.0
        )
        await ObservabilityEngine.shared.addSampler(errorSampler)
        
        // Setup cardinality guard
        let cardinalityGuard = CardinalityGuard(
            maxCardinality: 100,
            resetInterval: 300
        )
        
        let cardinalityEnricher = CardinalityEnricher(
            guard: cardinalityGuard,
            limiter: CardinalityLimiter(
                allowedDimensions: ["endpoint", "method", "status", "component"]
            ),
            monitor: CardinalityMonitor()
        )
        await ObservabilityEngine.shared.addEnricher(cardinalityEnricher)
        
        // Add breadcrumb hook
        await BreadcrumbRecorder.shared.addHook { breadcrumb in
            print("[Breadcrumb] \(breadcrumb.category.rawValue): \(breadcrumb.message)")
        }
        
        // Start initial trace
        _ = ContextPropagator.shared.startTrace(sampled: true)
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(TelemetryService())
    }
}