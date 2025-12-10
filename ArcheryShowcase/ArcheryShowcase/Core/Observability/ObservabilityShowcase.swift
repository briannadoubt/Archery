import Foundation
import SwiftUI
import Archery
import Charts

// MARK: - Observability Showcase
//
// This demonstrates Archery's full observability system:
// - Distributed tracing with spans
// - Real-time metrics collection
// - Structured logging
// - Breadcrumb trails for debugging
// - Cardinality monitoring

struct ObservabilityShowcaseView: View {
    @State private var showingDashboard = false
    @State private var isGeneratingData = false
    @State private var generatedSpans = 0
    @State private var generatedBreadcrumbs = 0

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Archery includes a complete observability system with OpenTelemetry-compatible tracing, metrics, logging, and breadcrumbs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        StatBadge(icon: "arrow.triangle.branch", value: "\(generatedSpans)", label: "Spans")
                        StatBadge(icon: "road.lanes", value: "\(generatedBreadcrumbs)", label: "Crumbs")
                    }
                }
            }

            Section("Live Dashboard") {
                Button {
                    showingDashboard = true
                } label: {
                    Label("Open Observability Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }

                Button {
                    Task { await generateSampleData() }
                } label: {
                    HStack {
                        Label("Generate Sample Data", systemImage: "wand.and.stars")
                        if isGeneratingData {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isGeneratingData)
            }

            Section("Tracing") {
                FeatureExplanation(
                    icon: "arrow.triangle.branch",
                    title: "Distributed Tracing",
                    description: "Track requests across services with trace/span IDs",
                    code: """
                    let span = propagator.startSpan(
                        name: "fetchUser",
                        attributes: ["user.id": userId]
                    )
                    defer { propagator.endSpan(span) }
                    """
                )

                FeatureExplanation(
                    icon: "arrow.up.arrow.down",
                    title: "Context Propagation",
                    description: "Automatically inject trace context into HTTP headers",
                    code: """
                    propagator.injectIntoHeaders(&headers)
                    // X-Trace-Id, X-Span-Id, X-Sampled
                    """
                )
            }

            Section("Breadcrumbs") {
                FeatureExplanation(
                    icon: "road.lanes",
                    title: "Breadcrumb Trail",
                    description: "Record navigation, UI events, network calls for crash context",
                    code: """
                    await BreadcrumbRecorder.shared.record(
                        message: "User tapped Buy button",
                        category: .ui,
                        level: .info,
                        data: ["product_id": productId]
                    )
                    """
                )
            }

            Section("Metrics & Cardinality") {
                FeatureExplanation(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Metrics Collection",
                    description: "Counters, gauges, histograms with OpenTelemetry export",
                    code: """
                    let counter = Counter(name: "api.requests")
                    counter.increment(attributes: ["endpoint": "/users"])
                    """
                )

                FeatureExplanation(
                    icon: "gauge.with.dots.needle.33percent",
                    title: "Cardinality Guard",
                    description: "Prevent metric explosion from high-cardinality labels",
                    code: """
                    let guard = CardinalityGuard(maxCardinality: 1000)
                    await guard.check(metricName, dimensions: labels)
                    """
                )
            }

            Section("Exporters") {
                ExporterRow(name: "Console", icon: "terminal", description: "Debug output to console")
                ExporterRow(name: "File", icon: "doc", description: "Rotate logs to disk")
                ExporterRow(name: "OpenTelemetry", icon: "cloud", description: "OTLP protocol export")
                ExporterRow(name: "Batch", icon: "tray.full", description: "Efficient batched export")
            }

            Section("Samplers") {
                SamplerRow(name: "Always/Never", description: "Sample all or none")
                SamplerRow(name: "Probability", description: "Random percentage sampling")
                SamplerRow(name: "Rate Limiting", description: "Max samples per second")
                SamplerRow(name: "Parent-Based", description: "Follow parent span decision")
                SamplerRow(name: "Error-Based", description: "Always sample on errors")
                SamplerRow(name: "Tail", description: "Decide after span completes")
            }
        }
        .navigationTitle("Observability")
        .fullScreenCover(isPresented: $showingDashboard) {
            NavigationStack {
                ObservabilityDashboard()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingDashboard = false }
                        }
                    }
            }
        }
    }

    @MainActor
    private func generateSampleData() async {
        isGeneratingData = true
        defer { isGeneratingData = false }

        let recorder = BreadcrumbRecorder.shared
        let propagator = ContextPropagator.shared

        // Generate navigation breadcrumbs
        let screens = ["Home", "Products", "Product Detail", "Cart", "Checkout"]
        for screen in screens {
            await recorder.record(
                category: .navigation,
                message: "Navigated to \(screen)",
                level: .info,
                data: ["screen": screen]
            )
            generatedBreadcrumbs += 1
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Generate UI breadcrumbs
        let actions = [
            ("Tapped Add to Cart", ["product_id": "SKU-123"]),
            ("Changed quantity", ["new_value": "2"]),
            ("Applied coupon", ["code": "SAVE10"]),
            ("Tapped Checkout", [:] as [String: String])
        ]
        for (message, data) in actions {
            await recorder.record(
                category: .ui,
                message: message,
                level: .info,
                data: data
            )
            generatedBreadcrumbs += 1
            try? await Task.sleep(for: .milliseconds(50))
        }

        // Generate network breadcrumbs
        let endpoints = ["/api/products", "/api/cart", "/api/checkout"]
        for endpoint in endpoints {
            await recorder.record(
                category: .network,
                message: "GET \(endpoint) - 200 OK",
                level: .info,
                data: ["duration_ms": "\(Int.random(in: 50...300))"]
            )
            generatedBreadcrumbs += 1
            try? await Task.sleep(for: .milliseconds(80))
        }

        // Generate some spans
        let trace = propagator.startTrace()
        _ = trace // Use trace context

        let parentSpan = propagator.startSpan(name: "checkout_flow", attributes: ["flow": "purchase"])
        generatedSpans += 1
        try? await Task.sleep(for: .milliseconds(100))

        let childSpan = propagator.startSpan(name: "validate_cart", attributes: ["items": "3"])
        generatedSpans += 1
        try? await Task.sleep(for: .milliseconds(50))
        propagator.endSpan(childSpan)

        let paymentSpan = propagator.startSpan(name: "process_payment", attributes: ["method": "card"])
        generatedSpans += 1
        try? await Task.sleep(for: .milliseconds(200))
        propagator.endSpan(paymentSpan)

        propagator.endSpan(parentSpan)

        // Record completion
        await recorder.record(
            category: .user,
            message: "Order completed successfully",
            level: .info,
            data: ["order_id": "ORD-\(Int.random(in: 10000...99999))"]
        )
        generatedBreadcrumbs += 1
    }
}

// MARK: - Supporting Views

private struct StatBadge: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(value)
                .font(.caption.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(Capsule())
    }
}

private struct FeatureExplanation: View {
    let icon: String
    let title: String
    let description: String
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(code)
                .font(.system(size: 10, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.vertical, 4)
    }
}

private struct ExporterRow: View {
    let name: String
    let icon: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.tint)

            VStack(alignment: .leading) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SamplerRow: View {
    let name: String
    let description: String

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name)
                    .font(.subheadline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

#Preview {
    NavigationStack {
        ObservabilityShowcaseView()
    }
}
