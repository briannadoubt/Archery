import SwiftUI

public struct SyncStatusView: View {
    var coordinator: SyncCoordinator
    private var connectivity = ConnectivityMonitor.shared
    
    public init(coordinator: SyncCoordinator) {
        self.coordinator = coordinator
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            statusIcon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.caption)
                    .fontWeight(.medium)
                
                if coordinator.pendingChanges > 0 {
                    Text("\(coordinator.pendingChanges) pending changes")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if let lastSync = coordinator.lastSyncTime {
                    Text("Last sync: \(lastSync, style: .relative)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if coordinator.syncState == .syncing {
                ProgressView(value: coordinator.syncProgress)
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
            } else if connectivity.isConnected {
                Button(action: {
                    Task {
                        await coordinator.forceSync()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        #if os(iOS)
        .background(Color(uiColor: .systemGray6))
        #else
        .background(Color.gray.opacity(0.1))
        #endif
        .cornerRadius(8)
    }

    private var statusIcon: some View {
        Group {
            switch coordinator.syncState {
            case .idle:
                Image(systemName: coordinator.pendingChanges > 0 ? "clock.badge.exclamationmark" : "checkmark.circle.fill")
                    .foregroundColor(coordinator.pendingChanges > 0 ? .orange : .green)
            case .syncing:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.blue)
            case .resolving:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.yellow)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            case .offline:
                Image(systemName: "wifi.slash")
                    .foregroundColor(.gray)
            }
        }
        .font(.system(size: 16))
    }
    
    private var statusText: String {
        switch coordinator.syncState {
        case .idle:
            return coordinator.pendingChanges > 0 ? "Changes pending" : "Synced"
        case .syncing:
            return "Syncing..."
        case .resolving:
            return "Resolving conflicts"
        case .failed:
            return "Sync failed"
        case .offline:
            return "Offline"
        }
    }
}

public struct SyncDiagnosticsView: View {
    var coordinator: SyncCoordinator
    @State private var showingDetails = false
    
    public init(coordinator: SyncCoordinator) {
        self.coordinator = coordinator
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            
            if showingDetails {
                diagnosticsContent
            }
        }
        .padding()
        #if os(iOS)
        .background(Color(uiColor: .systemGray6))
        #else
        .background(Color.gray.opacity(0.1))
        #endif
        .cornerRadius(12)
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sync Diagnostics")
                    .font(.headline)
                
                Text("Tap to \(showingDetails ? "hide" : "show") details")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { showingDetails.toggle() }) {
                Image(systemName: showingDetails ? "chevron.up" : "chevron.down")
                    .foregroundColor(.accentColor)
            }
        }
    }
    
    private var diagnosticsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            metricsSection
            
            Divider()
            
            syncHistorySection
            
            if !coordinator.conflicts.isEmpty {
                Divider()
                conflictsSection
            }
        }
    }
    
    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metrics")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 4) {
                GridRow {
                    Text("Total Syncs:")
                        .foregroundColor(.secondary)
                    Text("\(coordinator.metrics.syncAttempts)")
                }
                
                GridRow {
                    Text("Success Rate:")
                        .foregroundColor(.secondary)
                    Text("\(Int(coordinator.metrics.successRate * 100))%")
                        .foregroundColor(coordinator.metrics.successRate > 0.9 ? .green : .orange)
                }
                
                GridRow {
                    Text("Avg Duration:")
                        .foregroundColor(.secondary)
                    Text("\(coordinator.metrics.averageSyncTime, specifier: "%.2f")s")
                }
                
                GridRow {
                    Text("Conflicts:")
                        .foregroundColor(.secondary)
                    Text("\(coordinator.metrics.conflictsResolved)")
                }
            }
            .font(.caption)
        }
    }
    
    private var syncHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Syncs")
                .font(.subheadline)
                .fontWeight(.semibold)

            if let report = coordinator.cachedDiagnosticsReport {
                ForEach(report.recentSyncs.prefix(5), id: \.timestamp) { event in
                    HStack {
                        Image(systemName: event.success ? "checkmark.circle" : "xmark.circle")
                            .foregroundColor(event.success ? .green : .red)
                            .font(.caption)

                        Text(event.timestamp, style: .relative)
                            .font(.caption)

                        Spacer()

                        Text("\(event.changesSynced) changes")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if event.conflicts > 0 {
                            Text("\(event.conflicts) conflicts")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
            } else {
                Text("No sync history yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var conflictsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Conflicts")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.orange)
            
            ForEach(coordinator.conflicts) { conflict in
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .font(.caption)
                    
                    Text(conflict.key)
                        .font(.caption)
                    
                    Spacer()
                    
                    Button("Resolve") {
                        Task {
                            await coordinator.resolveConflict(conflict.id, resolution: .lastWriteWins)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

public struct MutationQueueView: View {
    var queue: MutationQueue
    @State private var showingFailed = false
    
    public init(queue: MutationQueue) {
        self.queue = queue
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            
            if !queue.pendingMutations.isEmpty {
                pendingSection
            }
            
            if !queue.failedMutations.isEmpty {
                failedSection
            }
            
            if queue.pendingMutations.isEmpty && queue.failedMutations.isEmpty {
                emptyState
            }
        }
        .padding()
        #if os(iOS)
        .background(Color(uiColor: .systemGray6))
        #else
        .background(Color.gray.opacity(0.1))
        #endif
        .cornerRadius(12)
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mutation Queue")
                    .font(.headline)
                
                if queue.isProcessing {
                    Label("Processing...", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            if let lastSync = queue.lastSyncDate {
                Text("Last: \(lastSync, style: .relative)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(queue.pendingMutations.count) Pending", systemImage: "clock")
                .font(.subheadline)
                .foregroundColor(.orange)
            
            ForEach(queue.pendingMutations.prefix(3)) { mutation in
                MutationRow(mutation: mutation)
            }
            
            if queue.pendingMutations.count > 3 {
                Text("And \(queue.pendingMutations.count - 3) more...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var failedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("\(queue.failedMutations.count) Failed", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundColor(.red)
                
                Spacer()
                
                Button("Retry All") {
                    Task {
                        await queue.retryAll()
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            
            if showingFailed {
                ForEach(queue.failedMutations) { mutation in
                    FailedMutationRow(mutation: mutation, queue: queue)
                }
            }
        }
        .onTapGesture {
            showingFailed.toggle()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundColor(.green)
            
            Text("All synced")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct MutationRow: View {
    let mutation: MutationRecord
    
    var body: some View {
        HStack {
            stateIcon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(mutation.mutationType)
                    .font(.caption)
                    .lineLimit(1)
                
                Text(mutation.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if mutation.retryCount > 0 {
                Text("Retry \(mutation.retryCount)")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var stateIcon: some View {
        Group {
            switch mutation.state {
            case .pending:
                Image(systemName: "clock")
                    .foregroundColor(.orange)
            case .inProgress:
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.6)
            case .completed:
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle")
                    .foregroundColor(.red)
            case .conflicted:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.yellow)
            }
        }
        .font(.caption)
    }
}

struct FailedMutationRow: View {
    let mutation: MutationRecord
    let queue: MutationQueue
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MutationRow(mutation: mutation)
            
            if let error = mutation.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
            
            HStack {
                Button("Retry") {
                    Task {
                        await queue.retry(mutation.id)
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}