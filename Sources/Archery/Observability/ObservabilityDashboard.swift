import SwiftUI
import Charts
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Dashboard View

@MainActor
public struct ObservabilityDashboard: View {
    @StateObject private var viewModel = ObservabilityDashboardViewModel()
    @State private var selectedTab = 0
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            TracingView(viewModel: viewModel)
                .tabItem {
                    Label("Tracing", systemImage: "arrow.triangle.branch")
                }
                .tag(0)
            
            MetricsView(viewModel: viewModel)
                .tabItem {
                    Label("Metrics", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(1)
            
            LogsView(viewModel: viewModel)
                .tabItem {
                    Label("Logs", systemImage: "doc.text")
                }
                .tag(2)
            
            BreadcrumbsView(viewModel: viewModel)
                .tabItem {
                    Label("Breadcrumbs", systemImage: "road.lanes")
                }
                .tag(3)
            
            CardinalityView(viewModel: viewModel)
                .tabItem {
                    Label("Cardinality", systemImage: "gauge.with.dots.needle.33percent")
                }
                .tag(4)
        }
        .task {
            await viewModel.startMonitoring()
        }
    }
}

// MARK: - Tracing View

@MainActor
struct TracingView: View {
    @ObservedObject var viewModel: ObservabilityDashboardViewModel
    @State private var selectedTrace: TraceInfo?
    
    var body: some View {
        NavigationSplitView {
            List(viewModel.traces, selection: $selectedTrace) { trace in
                TraceRow(trace: trace)
                    .tag(trace)
            }
            .navigationTitle("Traces")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear") {
                        Task {
                            await viewModel.clearTraces()
                        }
                    }
                }
            }
        } detail: {
            if let trace = selectedTrace {
                TraceDetailView(trace: trace)
            } else {
                ContentUnavailableView("Select a Trace", systemImage: "arrow.triangle.branch")
            }
        }
    }
}

@MainActor
struct TraceRow: View {
    let trace: TraceInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trace.rootSpan.name)
                    .font(.headline)
                Spacer()
                if trace.hasError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                }
            }
            
            HStack {
                Text("Duration: \(trace.duration, format: .number.precision(.fractionLength(2)))ms")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Spans: \(trace.spanCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("Trace ID: \(trace.traceId.prefix(8))...")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

@MainActor
struct TraceDetailView: View {
    let trace: TraceInfo
    @State private var expandedSpans: Set<String> = []
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Trace Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Trace Details")
                        .font(.title2)
                        .bold()
                    
                    LabeledContent("Trace ID", value: trace.traceId)
                        .font(.caption)
                    
                    LabeledContent("Start Time") {
                        Text(trace.startTime, format: .dateTime)
                    }
                    
                    LabeledContent("Duration") {
                        Text("\(trace.duration) ms")
                    }
                    
                    LabeledContent("Total Spans", value: "\(trace.spanCount)")
                }
                .padding()
                #if canImport(UIKit)
                .background(Color(UIColor.secondarySystemBackground))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                .cornerRadius(8)
                
                // Span Timeline
                VStack(alignment: .leading, spacing: 8) {
                    Text("Span Timeline")
                        .font(.headline)
                    
                    ForEach(trace.spans) { span in
                        SpanTimelineRow(
                            span: span,
                            totalDuration: trace.duration,
                            isExpanded: expandedSpans.contains(span.spanId),
                            onToggle: {
                                if expandedSpans.contains(span.spanId) {
                                    expandedSpans.remove(span.spanId)
                                } else {
                                    expandedSpans.insert(span.spanId)
                                }
                            }
                        )
                    }
                }
                .padding()
                #if canImport(UIKit)
                .background(Color(UIColor.secondarySystemBackground))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle(trace.rootSpan.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

@MainActor
struct SpanTimelineRow: View {
    let span: SpanInfo
    let totalDuration: Double
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Indentation for nested spans
                ForEach(0..<span.depth, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 20)
                }
                
                // Span bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: geometry.size.width)
                        
                        Rectangle()
                            .fill(span.hasError ? Color.red : Color.blue)
                            .frame(width: geometry.size.width * (span.duration / totalDuration))
                            .offset(x: geometry.size.width * (span.offset / totalDuration))
                    }
                }
                .frame(height: 20)
            }
            
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    
                    Text(span.name)
                        .font(.caption)
                    
                    Text("\(span.duration, format: .number.precision(.fractionLength(2)))ms")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if span.hasError {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(span.attributes.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack {
                            Text(key)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(String(describing: value))
                                .font(.caption2)
                        }
                    }
                }
                .padding(.leading, 20)
            }
        }
    }
}

// MARK: - Metrics View

@MainActor
struct MetricsView: View {
    @ObservedObject var viewModel: ObservabilityDashboardViewModel
    @State private var selectedMetric: String?
    @State private var timeRange = TimeRange.lastHour
    
    enum TimeRange: String, CaseIterable {
        case lastMinute = "1m"
        case last5Minutes = "5m"
        case last15Minutes = "15m"
        case lastHour = "1h"
        case last24Hours = "24h"
        
        var seconds: TimeInterval {
            switch self {
            case .lastMinute: return 60
            case .last5Minutes: return 300
            case .last15Minutes: return 900
            case .lastHour: return 3600
            case .last24Hours: return 86400
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            List(viewModel.metrics.keys.sorted(), id: \.self, selection: $selectedMetric) { metricName in
                MetricRow(
                    name: metricName,
                    dataPoints: viewModel.metrics[metricName] ?? []
                )
            }
            .navigationTitle("Metrics")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Time Range", selection: $timeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                }
            }
        } detail: {
            if let metricName = selectedMetric,
               let dataPoints = viewModel.metrics[metricName] {
                MetricDetailView(
                    metricName: metricName,
                    dataPoints: dataPoints,
                    timeRange: timeRange
                )
            } else {
                ContentUnavailableView("Select a Metric", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
    }
}

@MainActor
struct MetricRow: View {
    let name: String
    let dataPoints: [MetricDataPoint]
    
    var latestValue: Double? {
        dataPoints.last?.value
    }
    
    var trend: Double {
        guard dataPoints.count >= 2 else { return 0 }
        let recent = dataPoints.suffix(10)
        guard let first = recent.first?.value,
              let last = recent.last?.value else { return 0 }
        return last - first
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)
            
            HStack {
                if let value = latestValue {
                    Text(String(format: "%.2f", value))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if trend != 0 {
                    Image(systemName: trend > 0 ? "arrow.up.right" : "arrow.down.right")
                        .foregroundColor(trend > 0 ? .green : .red)
                        .font(.caption)
                }
                
                Spacer()
                
                Text("\(dataPoints.count) points")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

@MainActor
struct MetricDetailView: View {
    let metricName: String
    let dataPoints: [MetricDataPoint]
    let timeRange: MetricsView.TimeRange
    
    var filteredDataPoints: [MetricDataPoint] {
        let cutoff = Date().addingTimeInterval(-timeRange.seconds)
        return dataPoints.filter { $0.timestamp > cutoff }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Metric Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(metricName)
                        .font(.title2)
                        .bold()
                    
                    HStack {
                        StatCard(
                            title: "Current",
                            value: String(format: "%.2f", filteredDataPoints.last?.value ?? 0)
                        )
                        
                        StatCard(
                            title: "Average",
                            value: String(format: "%.2f", average(filteredDataPoints))
                        )
                        
                        StatCard(
                            title: "Min",
                            value: String(format: "%.2f", filteredDataPoints.map(\.value).min() ?? 0)
                        )
                        
                        StatCard(
                            title: "Max",
                            value: String(format: "%.2f", filteredDataPoints.map(\.value).max() ?? 0)
                        )
                    }
                }
                .padding()
                #if canImport(UIKit)
                .background(Color(UIColor.secondarySystemBackground))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                .cornerRadius(8)
                
                // Chart
                if #available(iOS 16.0, macOS 13.0, *) {
                    VStack(alignment: .leading) {
                        Text("Trend")
                            .font(.headline)
                        
                        Chart(filteredDataPoints) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(Color.blue)
                            
                            AreaMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(Color.blue.opacity(0.1))
                        }
                        .frame(height: 200)
                    }
                    .padding()
                    #if canImport(UIKit)
                .background(Color(UIColor.secondarySystemBackground))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                    .cornerRadius(8)
                }
                
                // Recent Values
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Values")
                        .font(.headline)
                    
                    ForEach(filteredDataPoints.suffix(20).reversed()) { point in
                        HStack {
                            Text(point.timestamp, format: .dateTime.hour().minute().second())
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text(String(format: "%.2f", point.value))
                                .font(.caption)
                        }
                    }
                }
                .padding()
                #if canImport(UIKit)
                .background(Color(UIColor.secondarySystemBackground))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle(metricName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func average(_ points: [MetricDataPoint]) -> Double {
        guard !points.isEmpty else { return 0 }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }
}

@MainActor
struct StatCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        #if canImport(UIKit)
        .background(Color(UIColor.tertiarySystemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .cornerRadius(4)
    }
}

// MARK: - Logs View

@MainActor
struct LogsView: View {
    @ObservedObject var viewModel: ObservabilityDashboardViewModel
    @State private var selectedLevel: LogEntry.Level?
    @State private var searchText = ""
    
    var filteredLogs: [LogEntryInfo] {
        viewModel.logs.filter { log in
            (selectedLevel == nil || log.level == selectedLevel) &&
            (searchText.isEmpty || log.message.localizedCaseInsensitiveContains(searchText))
        }
    }
    
    var body: some View {
        VStack {
            // Filters
            HStack {
                Picker("Level", selection: $selectedLevel) {
                    Text("All").tag(LogEntry.Level?.none)
                    ForEach([LogEntry.Level.trace, .debug, .info, .warning, .error, .critical], id: \.self) { level in
                        Text(level.rawValue.capitalized).tag(Optional(level))
                    }
                }
                .pickerStyle(.segmented)
                
                Button("Clear") {
                    Task {
                        await viewModel.clearLogs()
                    }
                }
            }
            .padding()
            
            // Log List
            List(filteredLogs) { log in
                LogRow(log: log)
            }
            .searchable(text: $searchText, prompt: "Search logs")
        }
        .navigationTitle("Logs")
    }
}

@MainActor
struct LogRow: View {
    let log: LogEntryInfo
    
    var levelColor: Color {
        switch log.level {
        case .trace, .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error, .critical: return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(levelColor)
                    .frame(width: 8, height: 8)
                
                Text(log.timestamp, format: .dateTime.hour().minute().second())
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(log.level.rawValue.uppercased())
                    .font(.caption)
                    .foregroundColor(levelColor)
                
                Spacer()
                
                if !log.traceId.isEmpty {
                    Text("Trace: \(log.traceId.prefix(8))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(log.message)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(3)
            
            if !log.attributes.isEmpty {
                Text(log.attributes.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Breadcrumbs View

@MainActor
struct BreadcrumbsView: View {
    @ObservedObject var viewModel: ObservabilityDashboardViewModel
    @State private var selectedCategory: Breadcrumb.Category?
    
    var filteredBreadcrumbs: [Breadcrumb] {
        viewModel.breadcrumbs.filter { breadcrumb in
            selectedCategory == nil || breadcrumb.category == selectedCategory
        }
    }
    
    var body: some View {
        VStack {
            // Category Filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    FilterChip(
                        title: "All",
                        isSelected: selectedCategory == nil,
                        action: { selectedCategory = nil }
                    )
                    
                    ForEach([Breadcrumb.Category.navigation, .ui, .network, .database, .error, .user], id: \.self) { category in
                        FilterChip(
                            title: category.rawValue.capitalized,
                            isSelected: selectedCategory == category,
                            action: { selectedCategory = category }
                        )
                    }
                }
                .padding(.horizontal)
            }
            
            // Breadcrumb List
            List(filteredBreadcrumbs) { breadcrumb in
                BreadcrumbRow(breadcrumb: breadcrumb)
            }
        }
        .navigationTitle("Breadcrumbs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear") {
                    Task {
                        await viewModel.clearBreadcrumbs()
                    }
                }
            }
        }
    }
}

@MainActor
struct BreadcrumbRow: View {
    let breadcrumb: Breadcrumb
    
    var categoryIcon: String {
        switch breadcrumb.category {
        case .navigation: return "arrow.right.square"
        case .ui: return "hand.tap"
        case .network: return "network"
        case .database: return "cylinder"
        case .custom: return "star"
        case .error: return "exclamationmark.triangle"
        case .debug: return "ladybug"
        case .user: return "person.circle"
        }
    }
    
    var body: some View {
        HStack {
            Image(systemName: categoryIcon)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(breadcrumb.message)
                    .font(.caption)
                
                HStack {
                    Text(breadcrumb.timestamp, format: .dateTime.hour().minute().second())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("[\(breadcrumb.level.rawValue)]")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

@MainActor
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                #if os(iOS)
                .background(isSelected ? Color.blue : Color(uiColor: .secondarySystemBackground))
                #else
                .background(isSelected ? Color.blue : Color(nsColor: .controlBackgroundColor))
                #endif
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(15)
        }
    }
}

// MARK: - Cardinality View

@MainActor
struct CardinalityView: View {
    @ObservedObject var viewModel: ObservabilityDashboardViewModel
    
    var body: some View {
        List {
            Section("High Cardinality Metrics") {
                ForEach(viewModel.highCardinalityMetrics, id: \.0) { metric, cardinality in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(metric)
                                .font(.headline)
                            Text("\(cardinality) unique combinations")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if cardinality > 1000 {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            
            Section("Cardinality Alerts") {
                ForEach(viewModel.cardinalityAlerts, id: \.metricName) { alert in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(alert.metricName)
                                .font(.headline)
                            Spacer()
                            Text(alert.timestamp, format: .dateTime.hour().minute())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("Cardinality: \(alert.cardinality) (threshold: \(alert.threshold))")
                            .font(.caption)
                            .foregroundColor(.red)
                        
                        if let growthRate = alert.growthRate {
                            Text("Growth rate: \(String(format: "%.1f", growthRate)) dimensions/sec")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Cardinality")
    }
}

// MARK: - View Model

@MainActor
public class ObservabilityDashboardViewModel: ObservableObject {
    @Published var traces: [TraceInfo] = []
    @Published var metrics: [String: [MetricDataPoint]] = [:]
    @Published var logs: [LogEntryInfo] = []
    @Published var breadcrumbs: [Breadcrumb] = []
    @Published var highCardinalityMetrics: [(String, Int)] = []
    @Published var cardinalityAlerts: [CardinalityMonitor.CardinalityAlert] = []
    
    private let monitor = CardinalityMonitor()
    private var monitoringTask: Task<Void, Never>?
    
    public init() {}
    
    public func startMonitoring() async {
        monitoringTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
    }
    
    public func stopMonitoring() {
        monitoringTask?.cancel()
    }
    
    public func refresh() async {
        // Get breadcrumbs
        breadcrumbs = await BreadcrumbRecorder.shared.getBreadcrumbs(limit: 100)
        
        // Get cardinality info
        highCardinalityMetrics = await monitor.getHighCardinalityMetrics()
        cardinalityAlerts = await monitor.getAlerts()
        
        // Note: In a real app, traces, metrics, and logs would come from the exporters
        // This is just for demonstration
    }
    
    public func clearTraces() async {
        traces.removeAll()
    }
    
    public func clearLogs() async {
        logs.removeAll()
    }
    
    public func clearBreadcrumbs() async {
        await BreadcrumbRecorder.shared.clear()
        breadcrumbs.removeAll()
    }
    
    public func clearMetrics() async {
        metrics.removeAll()
    }
}

// MARK: - Supporting Types

public struct TraceInfo: Identifiable, Hashable {
    public let id = UUID()
    public let traceId: String
    public let startTime: Date
    public let duration: Double
    public let spanCount: Int
    public let rootSpan: SpanInfo
    public let spans: [SpanInfo]
    public let hasError: Bool
}

public struct SpanInfo: Identifiable, Hashable {
    public let id = UUID()
    public let spanId: String
    public let parentSpanId: String?
    public let name: String
    public let startTime: Date
    public let duration: Double
    public let offset: Double
    public let depth: Int
    public let attributes: [String: String]
    public let hasError: Bool
}

public struct MetricDataPoint: Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let value: Double
    public let attributes: [String: String]
}

public struct LogEntryInfo: Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let level: LogEntry.Level
    public let message: String
    public let traceId: String
    public let spanId: String
    public let attributes: [String: String]
}