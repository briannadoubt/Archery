import SwiftUI
import Archery

/// Interactive view for demonstrating runtime performance tracing
struct PerformanceTracingView: View {
    @State private var isTracingEnabled = false
    @State private var spanRecords: [SpanStatisticsCollector.SpanRecord] = []
    @State private var statistics: SpanStatistics?
    @State private var isRunningOperations = false

    @Query(\.byCreatedAt)
    var allTasks: [TaskItem]

    @Environment(\.databaseWriter) private var writer

    var body: some View {
        List {
            // Toggle Section
            Section {
                Toggle(isOn: $isTracingEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Performance Tracing")
                            .font(.headline)
                        Text("Enable to record spans for database and network operations")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: isTracingEnabled) { _, newValue in
                    Task { @MainActor in
                        FeatureFlagManager.shared.override(
                            BuiltInFlags.PerformanceTracingFlag.self,
                            with: newValue
                        )
                    }
                }
            } header: {
                Label("Configuration", systemImage: "slider.horizontal.3")
            } footer: {
                Text("When enabled, macro-generated code (@Persistable, @DatabaseRepository, @APIClient) will emit performance spans.")
            }

            // Trigger Operations Section
            Section {
                Button {
                    runTestOperations()
                } label: {
                    HStack {
                        if isRunningOperations {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(isRunningOperations ? "Running..." : "Run Test Operations")
                    }
                }
                .disabled(isRunningOperations || !isTracingEnabled)

                Button {
                    refreshStatistics()
                } label: {
                    Label("Refresh Statistics", systemImage: "arrow.clockwise")
                }

                Button(role: .destructive) {
                    clearStatistics()
                } label: {
                    Label("Clear All Spans", systemImage: "trash")
                }
            } header: {
                Label("Actions", systemImage: "bolt.fill")
            } footer: {
                if !isTracingEnabled {
                    Text("Enable performance tracing to run test operations and collect spans.")
                }
            }

            // Statistics Section
            if let stats = statistics, stats.totalSpans > 0 {
                Section {
                    TracingStatRow(label: "Total Spans", value: "\(stats.totalSpans)")

                    ForEach(Array(stats.byCategory.keys.sorted()), id: \.self) { category in
                        if let categoryStats = stats.byCategory[category] {
                            DisclosureGroup {
                                TracingStatRow(label: "Count", value: "\(categoryStats.count)")
                                TracingStatRow(label: "Mean", value: formatDuration(categoryStats.meanDuration))
                                TracingStatRow(label: "P50", value: formatDuration(categoryStats.p50Duration))
                                TracingStatRow(label: "P95", value: formatDuration(categoryStats.p95Duration))
                                TracingStatRow(label: "Min", value: formatDuration(categoryStats.minDuration))
                                TracingStatRow(label: "Max", value: formatDuration(categoryStats.maxDuration))
                            } label: {
                                HStack {
                                    CategoryBadge(category: category)
                                    Spacer()
                                    Text("\(categoryStats.count) spans")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Label("Statistics", systemImage: "chart.bar")
                }
            }

            // Recent Spans Section
            if !spanRecords.isEmpty {
                Section {
                    ForEach(spanRecords.prefix(20)) { record in
                        SpanRecordRow(record: record)
                    }
                } header: {
                    Label("Recent Spans (\(spanRecords.count))", systemImage: "list.bullet")
                }
            }

            // Usage Section
            Section {
                Text("Performance tracing is controlled by the `BuiltInFlags.PerformanceTracingFlag`. When enabled, the `OperationTracer` utility wraps operations with spans that are recorded to the observability system.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TracingCodeSnippetView("""
                // Enable tracing programmatically
                FeatureFlagManager.shared.override(
                    BuiltInFlags.PerformanceTracingFlag.self,
                    with: true
                )

                // Generated code automatically wraps operations:
                // @DatabaseRepository -> traceDatabase()
                // @APIClient -> traceNetwork()
                // @Persistable EntityQuery -> trace()
                """)
            } header: {
                Label("Usage", systemImage: "doc.text")
            }
        }
        .navigationTitle("Performance Tracing")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .onAppear {
            loadInitialState()
        }
    }

    // MARK: - Actions

    private func loadInitialState() {
        Task { @MainActor in
            isTracingEnabled = FeatureFlagManager.shared.isEnabled(
                for: BuiltInFlags.PerformanceTracingFlag.self
            )
        }
        refreshStatistics()
    }

    private func runTestOperations() {
        isRunningOperations = true

        Task {
            // Run a variety of database operations to generate spans
            guard let writer else {
                await MainActor.run { isRunningOperations = false }
                return
            }

            // Create a test task
            let testTask = TaskItem(
                title: "Trace Test \(Date().formatted(date: .omitted, time: .shortened))",
                status: .todo,
                priority: .medium
            )

            // Insert
            _ = try? await writer.insert(testTask)

            // Fetch all
            _ = allTasks

            // Update
            var updated = testTask
            updated.status = .completed
            _ = try? await writer.update(updated)

            // Delete
            _ = try? await writer.delete(TaskItem.self, id: testTask.id)

            // Small delay to let spans propagate
            try? await Task.sleep(nanoseconds: 100_000_000)

            await MainActor.run {
                isRunningOperations = false
                refreshStatistics()
            }
        }
    }

    private func refreshStatistics() {
        Task {
            let records = await SpanStatisticsCollector.shared.getRecords()
            let stats = await SpanStatisticsCollector.shared.getStatistics()

            await MainActor.run {
                spanRecords = records.reversed() // Most recent first
                statistics = stats
            }
        }
    }

    private func clearStatistics() {
        Task {
            await SpanStatisticsCollector.shared.clear()
            await MainActor.run {
                spanRecords = []
                statistics = nil
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 0.001 {
            return String(format: "%.2f \u{00B5}s", seconds * 1_000_000)
        } else if seconds < 1 {
            return String(format: "%.2f ms", seconds * 1000)
        } else {
            return String(format: "%.2f s", seconds)
        }
    }
}

// MARK: - Supporting Views

private struct TracingStatRow: View {
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

private struct CategoryBadge: View {
    let category: String

    var body: some View {
        Text(category.capitalized)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(categoryColor.opacity(0.2))
            .foregroundStyle(categoryColor)
            .clipShape(Capsule())
    }

    private var categoryColor: Color {
        switch category {
        case "database": return .blue
        case "network": return .green
        case "cache": return .orange
        case "query": return .purple
        case "migration": return .red
        default: return .gray
        }
    }
}

private struct SpanRecordRow: View {
    let record: SpanStatisticsCollector.SpanRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.name)
                    .font(.headline)
                Spacer()
                Text(formatDuration(record.duration))
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                CategoryBadge(category: record.category)

                Text(statusIcon)
                    .font(.caption)

                Text(record.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: String {
        switch record.status {
        case "ok": return "checkmark.circle"
        case "error": return "xmark.circle"
        default: return "circle"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 0.001 {
            return String(format: "%.1f\u{00B5}s", seconds * 1_000_000)
        } else {
            return String(format: "%.2fms", seconds * 1000)
        }
    }
}

private struct TracingCodeSnippetView: View {
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
        PerformanceTracingView()
    }
}
