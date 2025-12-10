import XCTest
@testable import Archery

final class ObservabilityTests: XCTestCase {
    
    // MARK: - Correlation Context Tests
    
    func testCorrelationContextGeneration() {
        let context = CorrelationContext()
        
        XCTAssertFalse(context.traceId.isEmpty)
        XCTAssertFalse(context.spanId.isEmpty)
        XCTAssertNil(context.parentSpanId)
        XCTAssertTrue(context.baggage.isEmpty)
        XCTAssertTrue(context.sampled)
    }
    
    func testCorrelationContextWithValues() {
        let context = CorrelationContext(
            traceId: "trace123",
            spanId: "span456",
            parentSpanId: "parent789",
            baggage: ["key": "value"],
            sampled: false
        )
        
        XCTAssertEqual(context.traceId, "trace123")
        XCTAssertEqual(context.spanId, "span456")
        XCTAssertEqual(context.parentSpanId, "parent789")
        XCTAssertEqual(context.baggage["key"], "value")
        XCTAssertFalse(context.sampled)
    }
    
    func testCreateChildContext() {
        let parent = CorrelationContext(
            traceId: "trace123",
            spanId: "span456",
            baggage: ["key": "value"]
        )
        
        let child = parent.createChildContext()
        
        XCTAssertEqual(child.traceId, parent.traceId)
        XCTAssertNotEqual(child.spanId, parent.spanId)
        XCTAssertEqual(child.parentSpanId, parent.spanId)
        XCTAssertEqual(child.baggage, parent.baggage)
        XCTAssertEqual(child.sampled, parent.sampled)
    }
    
    func testWithBaggage() {
        let context = CorrelationContext()
        let updated = context.withBaggage("key", value: "value")
        
        XCTAssertTrue(context.baggage.isEmpty)
        XCTAssertEqual(updated.baggage["key"], "value")
        XCTAssertEqual(updated.traceId, context.traceId)
        XCTAssertEqual(updated.spanId, context.spanId)
    }
    
    // MARK: - Context Propagator Tests
    
    @MainActor
    func testContextPropagatorStartTrace() {
        let propagator = ContextPropagator.shared
        let context = propagator.startTrace(sampled: false)
        
        XCTAssertEqual(propagator.currentContext.traceId, context.traceId)
        XCTAssertFalse(context.sampled)
    }
    
    @MainActor
    func testContextPropagatorStartSpan() {
        let propagator = ContextPropagator.shared
        let initialContext = propagator.startTrace()
        
        let span = propagator.startSpan(name: "test-span", attributes: ["key": "value"])
        
        XCTAssertEqual(span.name, "test-span")
        XCTAssertEqual(span.context.traceId, initialContext.traceId)
        XCTAssertEqual(span.context.parentSpanId, initialContext.spanId)
        XCTAssertEqual(span.attributes["key"] as? String, "value")
    }
    
    @MainActor
    func testContextPropagatorEndSpan() {
        let propagator = ContextPropagator.shared
        _ = propagator.startTrace()
        let parentContext = propagator.currentContext
        
        let span = propagator.startSpan(name: "test-span")
        let childContext = propagator.currentContext
        
        propagator.endSpan(span)
        
        XCTAssertEqual(propagator.currentContext.spanId, parentContext.spanId)
        XCTAssertNotEqual(propagator.currentContext.spanId, childContext.spanId)
        XCTAssertNotNil(span.endTime)
    }
    
    @MainActor
    func testInjectIntoHeaders() {
        let propagator = ContextPropagator.shared
        let context = CorrelationContext(
            traceId: "trace123",
            spanId: "span456",
            parentSpanId: "parent789",
            baggage: ["key": "value"],
            sampled: true
        )
        
        _ = propagator.withContext(context) {
            var headers = [String: String]()
            propagator.injectIntoHeaders(&headers)
            
            XCTAssertEqual(headers["X-Trace-Id"], "trace123")
            XCTAssertEqual(headers["X-Span-Id"], "span456")
            XCTAssertEqual(headers["X-Parent-Span-Id"], "parent789")
            XCTAssertEqual(headers["X-Sampled"], "1")
            XCTAssertEqual(headers["X-Baggage-key"], "value")
        }
    }
    
    @MainActor
    func testExtractFromHeaders() {
        let propagator = ContextPropagator.shared
        let headers = [
            "X-Trace-Id": "trace123",
            "X-Span-Id": "span456",
            "X-Parent-Span-Id": "parent789",
            "X-Sampled": "1",
            "X-Baggage-key": "value"
        ]
        
        let context = propagator.extractFromHeaders(headers)
        
        XCTAssertEqual(context.traceId, "trace123")
        XCTAssertEqual(context.spanId, "span456")
        XCTAssertEqual(context.parentSpanId, "parent789")
        XCTAssertTrue(context.sampled)
        XCTAssertEqual(context.baggage["key"], "value")
    }
    
    // MARK: - Span Tests
    
    func testSpanCreation() {
        let context = CorrelationContext()
        let span = Span(
            name: "test-span",
            context: context,
            attributes: ["key": "value"]
        )
        
        XCTAssertEqual(span.name, "test-span")
        XCTAssertEqual(span.context.traceId, context.traceId)
        XCTAssertEqual(span.attributes["key"] as? String, "value")
        XCTAssertNil(span.endTime)
        XCTAssertEqual(span.status, .unset)
    }
    
    func testSpanSetAttribute() {
        let span = Span(name: "test", context: CorrelationContext())
        span.setAttribute("key", value: "value")
        
        XCTAssertEqual(span.attributes["key"] as? String, "value")
    }
    
    func testSpanAddEvent() {
        let span = Span(name: "test", context: CorrelationContext())
        span.addEvent("test-event", attributes: ["key": "value"])
        
        XCTAssertEqual(span.events.count, 1)
        XCTAssertEqual(span.events[0].name, "test-event")
        XCTAssertEqual(span.events[0].attributes["key"] as? String, "value")
    }
    
    func testSpanSetStatus() {
        let span = Span(name: "test", context: CorrelationContext())
        span.setStatus(.error(nil), message: "Error occurred")
        
        if case .error = span.status {
            XCTAssertEqual(span.attributes["status.message"] as? String, "Error occurred")
        } else {
            XCTFail("Expected error status")
        }
    }
    
    func testSpanEnd() {
        let span = Span(name: "test", context: CorrelationContext())
        span.end()
        
        XCTAssertNotNil(span.endTime)
        XCTAssertNotNil(span.duration)
        
        // Ending again should not change end time
        let firstEndTime = span.endTime
        span.end()
        XCTAssertEqual(span.endTime, firstEndTime)
    }
    
    // MARK: - Breadcrumb Tests
    
    func testBreadcrumbCreation() {
        let breadcrumb = Breadcrumb(
            category: .navigation,
            message: "Navigated to screen",
            level: .info,
            data: ["screen": "home"]
        )
        
        XCTAssertEqual(breadcrumb.category, .navigation)
        XCTAssertEqual(breadcrumb.message, "Navigated to screen")
        XCTAssertEqual(breadcrumb.level, .info)
        XCTAssertEqual(breadcrumb.data["screen"], "home")
        XCTAssertNotNil(breadcrumb.context)
    }
    
    func testBreadcrumbRecorder() async {
        let recorder = BreadcrumbRecorder.shared
        await recorder.clear()
        
        await recorder.record(
            category: .ui,
            message: "Button tapped",
            level: .debug
        )
        
        let breadcrumbs = await recorder.getBreadcrumbs()
        XCTAssertEqual(breadcrumbs.count, 1)
        XCTAssertEqual(breadcrumbs[0].category, .ui)
        XCTAssertEqual(breadcrumbs[0].message, "Button tapped")
    }
    
    func testBreadcrumbRecorderMaxLimit() async {
        let recorder = BreadcrumbRecorder(maxBreadcrumbs: 5)

        for i in 0..<10 {
            await recorder.record(
                category: Breadcrumb.Category.debug,
                message: "Message \(i)"
            )
        }

        let breadcrumbs = await recorder.getBreadcrumbs()
        XCTAssertEqual(breadcrumbs.count, 5)
        XCTAssertEqual(breadcrumbs[0].message, "Message 5")
        XCTAssertEqual(breadcrumbs[4].message, "Message 9")
    }
    
    // MARK: - Metrics Tests
    
    func testCounterMetric() {
        let counter = Counter(
            name: "api.requests",
            value: 1,
            unit: .count,
            attributes: ["endpoint": "/users"]
        )
        
        XCTAssertEqual(counter.name, "api.requests")
        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(counter.unit, .count)
        XCTAssertEqual(counter.attributes["endpoint"] as? String, "/users")
    }
    
    func testGaugeMetric() {
        let gauge = Gauge(
            name: "memory.usage",
            value: 150.5,
            unit: .bytes,
            attributes: ["process": "main"]
        )
        
        XCTAssertEqual(gauge.name, "memory.usage")
        XCTAssertEqual(gauge.value, 150.5)
        XCTAssertEqual(gauge.unit, .bytes)
    }
    
    func testHistogramMetric() {
        let histogram = Histogram(
            name: "response.time",
            value: 0.125,
            unit: .seconds,
            buckets: [0.01, 0.05, 0.1, 0.5, 1.0]
        )
        
        XCTAssertEqual(histogram.name, "response.time")
        XCTAssertEqual(histogram.value, 0.125)
        XCTAssertEqual(histogram.buckets.count, 5)
    }
    
    // MARK: - Sampler Tests
    
    func testAlwaysSampleSampler() {
        let sampler = AlwaysSampleSampler()
        let span = Span(name: "test", context: CorrelationContext())
        
        XCTAssertTrue(sampler.shouldSample(span: span))
        XCTAssertTrue(sampler.shouldSampleMetric(metric: Counter(name: "test")))
        XCTAssertTrue(sampler.shouldSampleLog(log: LogEntry(level: .info, message: "test")))
    }
    
    func testNeverSampleSampler() {
        let sampler = NeverSampleSampler()
        let span = Span(name: "test", context: CorrelationContext())
        
        XCTAssertFalse(sampler.shouldSample(span: span))
        XCTAssertFalse(sampler.shouldSampleMetric(metric: Counter(name: "test")))
        XCTAssertFalse(sampler.shouldSampleLog(log: LogEntry(level: .info, message: "test")))
    }
    
    func testProbabilitySampler() {
        let sampler = ProbabilitySampler(probability: 0.5)
        var sampled = 0
        let iterations = 1000
        
        for _ in 0..<iterations {
            let context = CorrelationContext()
            let span = Span(name: "test", context: context)
            if sampler.shouldSample(span: span) {
                sampled += 1
            }
        }
        
        // Should be roughly 50% with some variance
        let ratio = Double(sampled) / Double(iterations)
        XCTAssertTrue(ratio > 0.4 && ratio < 0.6)
    }
    
    func testErrorBasedSampler() {
        let sampler = ErrorBasedSampler(
            baselineProbability: 0.0,
            errorProbability: 1.0
        )
        
        let normalSpan = Span(name: "normal", context: CorrelationContext())
        normalSpan.setStatus(.ok)
        
        let errorSpan = Span(name: "error", context: CorrelationContext())
        errorSpan.setStatus(.error(nil))
        
        // Normal spans should not be sampled with 0% baseline
        XCTAssertFalse(sampler.shouldSample(span: normalSpan))
        
        // Error spans should always be sampled with 100% error probability
        XCTAssertTrue(sampler.shouldSample(span: errorSpan))
    }
    
    // MARK: - Cardinality Tests
    
    func testCardinalityGuard() async {
        let cardinalityGuard = CardinalityGuard(maxCardinality: 3)

        let result1 = await cardinalityGuard.checkCardinality(
            metricName: "test.metric",
            attributes: ["key": "value1"]
        )
        XCTAssertEqual(result1, .accepted)

        let result2 = await cardinalityGuard.checkCardinality(
            metricName: "test.metric",
            attributes: ["key": "value2"]
        )
        XCTAssertEqual(result2, .accepted)

        let result3 = await cardinalityGuard.checkCardinality(
            metricName: "test.metric",
            attributes: ["key": "value3"]
        )
        XCTAssertEqual(result3, .accepted)

        // Fourth unique combination should be rejected
        let result4 = await cardinalityGuard.checkCardinality(
            metricName: "test.metric",
            attributes: ["key": "value4"]
        )
        if case .rejected = result4 {
            // Expected
        } else {
            XCTFail("Expected rejection")
        }

        // Existing combination should be accepted
        let result5 = await cardinalityGuard.checkCardinality(
            metricName: "test.metric",
            attributes: ["key": "value1"]
        )
        XCTAssertEqual(result5, .accepted)

        let cardinality = await cardinalityGuard.getCardinality(for: "test.metric")
        XCTAssertEqual(cardinality, 3)
    }
    
    func testCardinalityLimiter() {
        let limiter = CardinalityLimiter(
            allowedDimensions: ["endpoint", "status"],
            maxDimensionValues: ["status": 5]
        )
        
        let attributes: [String: String] = [
            "endpoint": "/users",
            "status": "200",
            "forbidden": "value",
            "user_id": "12345"
        ]

        let limited = limiter.limitAttributes(attributes)
        
        XCTAssertEqual(limited.count, 2)
        XCTAssertNotNil(limited["endpoint"])
        XCTAssertNotNil(limited["status"])
        XCTAssertNil(limited["forbidden"])
        XCTAssertNil(limited["user_id"])
    }
    
    func testDimensionReducer() {
        let reducer = DimensionReducer(strategy: .keepSpecific(["important", "critical"]))

        let attributes: [String: String] = [
            "important": "value1",
            "unimportant": "value2",
            "critical": "value3",
            "optional": "value4"
        ]

        let reduced = reducer.reduce(attributes)

        XCTAssertEqual(reduced.count, 2)
        XCTAssertNotNil(reduced["important"])
        XCTAssertNotNil(reduced["critical"])
        XCTAssertNil(reduced["unimportant"])
        XCTAssertNil(reduced["optional"])
    }
    
    // MARK: - Exporter Tests
    
    func testConsoleExporter() async throws {
        let exporter = ConsoleExporter(prettyPrint: true)
        
        let span = Span(
            name: "test-span",
            context: CorrelationContext(),
            attributes: ["key": "value"]
        )
        span.end()
        
        try await exporter.export(spans: [span])
        try await exporter.export(metrics: [Counter(name: "test.counter")])
        try await exporter.export(logs: [LogEntry(level: .info, message: "test")])
        
        try await exporter.flush()
        try await exporter.shutdown()
        
        // Console exporter should not throw
        XCTAssertTrue(true)
    }
    
    func testBatchExporter() async throws {
        let mockExporter = MockExporter()
        let batchExporter = BatchExporter(
            wrapped: mockExporter,
            batchSize: 2,
            flushInterval: 10
        )
        
        // Send 3 spans - first 2 should batch, third waits
        for i in 0..<3 {
            let span = Span(name: "span-\(i)", context: CorrelationContext())
            try await batchExporter.export(spans: [span])
        }
        
        // First batch should have been sent
        let exportedCount = await mockExporter.exportedSpansCount
        XCTAssertEqual(exportedCount, 2)
        
        // Flush remaining
        try await batchExporter.flush()
        let finalCount = await mockExporter.exportedSpansCount
        XCTAssertEqual(finalCount, 3)
        
        try await batchExporter.shutdown()
    }
}

// MARK: - Mock Exporter

actor MockExporter: TelemetryExporter {
    private var spans: [Span] = []
    private var metrics: [any Metric] = []
    private var logs: [LogEntry] = []
    
    var exportedSpansCount: Int {
        spans.count
    }
    
    func export(spans: [Span]) async throws {
        self.spans.append(contentsOf: spans)
    }
    
    func export(metrics: [any Metric]) async throws {
        self.metrics.append(contentsOf: metrics)
    }
    
    func export(logs: [LogEntry]) async throws {
        self.logs.append(contentsOf: logs)
    }
    
    func flush() async throws {
        // No-op
    }
    
    func shutdown() async throws {
        spans.removeAll()
        metrics.removeAll()
        logs.removeAll()
    }
}