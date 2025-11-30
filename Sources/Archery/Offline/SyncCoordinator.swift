import Foundation
import Combine
import SwiftUI

@MainActor
public final class SyncCoordinator: ObservableObject {
    @Published public private(set) var syncState: SyncState = .idle
    @Published public private(set) var lastSyncTime: Date?
    @Published public private(set) var pendingChanges: Int = 0
    @Published public private(set) var syncProgress: Double = 0
    @Published public private(set) var conflicts: [ConflictRecord] = []
    @Published public private(set) var metrics: SyncMetrics
    
    private let mutationQueue: MutationQueue
    private let connectivity: ConnectivityMonitor
    private var syncTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let diagnostics: SyncDiagnostics
    
    public enum SyncState: String, CaseIterable {
        case idle
        case syncing
        case resolving
        case failed
        case offline
    }
    
    public init(
        mutationQueue: MutationQueue,
        connectivity: ConnectivityMonitor = .shared
    ) {
        self.mutationQueue = mutationQueue
        self.connectivity = connectivity
        self.metrics = SyncMetrics()
        self.diagnostics = SyncDiagnostics()
        
        setupBindings()
        startMonitoring()
    }
    
    private func setupBindings() {
        mutationQueue.$pendingMutations
            .map { $0.count }
            .assign(to: &$pendingChanges)
        
        connectivity.$isConnected
            .sink { [weak self] isConnected in
                if !isConnected {
                    self?.syncState = .offline
                } else if self?.syncState == .offline {
                    self?.syncState = .idle
                    Task { [weak self] in
                        await self?.sync()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func startMonitoring() {
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    if self?.connectivity.isConnected == true {
                        await self?.sync()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    public func sync() async {
        guard connectivity.isConnected else {
            syncState = .offline
            return
        }
        
        guard syncState != .syncing else { return }
        
        syncState = .syncing
        syncProgress = 0
        
        let startTime = Date()
        metrics.syncAttempts += 1
        
        do {
            await mutationQueue.processQueue()
            
            syncProgress = 0.5
            
            if !conflicts.isEmpty {
                syncState = .resolving
                await resolveConflicts()
            }
            
            syncProgress = 1.0
            syncState = .idle
            lastSyncTime = Date()
            
            let duration = Date().timeIntervalSince(startTime)
            metrics.successfulSyncs += 1
            metrics.totalSyncTime += duration
            metrics.lastSyncDuration = duration
            
            await diagnostics.recordSync(
                success: true,
                duration: duration,
                changesSync: pendingChanges,
                conflicts: conflicts.count
            )
        } catch {
            syncState = .failed
            metrics.failedSyncs += 1
            
            await diagnostics.recordSync(
                success: false,
                duration: Date().timeIntervalSince(startTime),
                changesSync: pendingChanges,
                conflicts: conflicts.count,
                error: error
            )
        }
    }
    
    public func forceSync() async {
        syncTask?.cancel()
        syncTask = Task {
            await sync()
        }
    }
    
    public func resolveConflict(_ conflictId: String, resolution: ConflictResolution) async {
        guard let index = conflicts.firstIndex(where: { $0.id == conflictId }) else {
            return
        }
        
        let conflict = conflicts[index]
        conflicts.remove(at: index)
        
        await diagnostics.recordConflictResolution(
            conflict: conflict,
            resolution: resolution
        )
    }
    
    private func resolveConflicts() async {
        for conflict in conflicts {
            await resolveConflict(conflict.id, resolution: .lastWriteWins)
        }
    }
    
    public func getDiagnostics() -> SyncDiagnostics {
        diagnostics
    }
}

public struct ConflictRecord: Identifiable {
    public let id = UUID().uuidString
    public let timestamp: Date
    public let localValue: Any
    public let remoteValue: Any
    public let key: String
    
    public init(key: String, localValue: Any, remoteValue: Any) {
        self.key = key
        self.localValue = localValue
        self.remoteValue = remoteValue
        self.timestamp = Date()
    }
}

public struct SyncMetrics {
    public var syncAttempts: Int = 0
    public var successfulSyncs: Int = 0
    public var failedSyncs: Int = 0
    public var totalSyncTime: TimeInterval = 0
    public var lastSyncDuration: TimeInterval = 0
    public var conflictsResolved: Int = 0
    public var dataTransferred: Int64 = 0
    
    public var averageSyncTime: TimeInterval {
        guard successfulSyncs > 0 else { return 0 }
        return totalSyncTime / Double(successfulSyncs)
    }
    
    public var successRate: Double {
        guard syncAttempts > 0 else { return 0 }
        return Double(successfulSyncs) / Double(syncAttempts)
    }
}

public actor SyncDiagnostics {
    private var syncHistory: [SyncEvent] = []
    private var conflictHistory: [ConflictEvent] = []
    private let maxHistorySize = 100
    
    public struct SyncEvent {
        public let timestamp: Date
        public let success: Bool
        public let duration: TimeInterval
        public let changesSynced: Int
        public let conflicts: Int
        public let error: Error?
    }
    
    public struct ConflictEvent {
        public let timestamp: Date
        public let key: String
        public let resolution: ConflictResolution
    }
    
    public func recordSync(
        success: Bool,
        duration: TimeInterval,
        changesSync: Int,
        conflicts: Int,
        error: Error? = nil
    ) {
        let event = SyncEvent(
            timestamp: Date(),
            success: success,
            duration: duration,
            changesSynced: changesSync,
            conflicts: conflicts,
            error: error
        )
        
        syncHistory.append(event)
        
        if syncHistory.count > maxHistorySize {
            syncHistory.removeFirst(syncHistory.count - maxHistorySize)
        }
    }
    
    public func recordConflictResolution(
        conflict: ConflictRecord,
        resolution: ConflictResolution
    ) {
        let event = ConflictEvent(
            timestamp: Date(),
            key: conflict.key,
            resolution: resolution
        )
        
        conflictHistory.append(event)
        
        if conflictHistory.count > maxHistorySize {
            conflictHistory.removeFirst(conflictHistory.count - maxHistorySize)
        }
    }
    
    public func getSyncHistory() -> [SyncEvent] {
        syncHistory
    }
    
    public func getConflictHistory() -> [ConflictEvent] {
        conflictHistory
    }
    
    public func generateReport() -> SyncDiagnosticsReport {
        let successfulSyncs = syncHistory.filter { $0.success }
        let failedSyncs = syncHistory.filter { !$0.success }
        
        let totalDuration = successfulSyncs.reduce(0) { $0 + $1.duration }
        let averageDuration = successfulSyncs.isEmpty ? 0 : totalDuration / Double(successfulSyncs.count)
        
        let totalChanges = syncHistory.reduce(0) { $0 + $1.changesSynced }
        let totalConflicts = syncHistory.reduce(0) { $0 + $1.conflicts }
        
        return SyncDiagnosticsReport(
            totalSyncs: syncHistory.count,
            successfulSyncs: successfulSyncs.count,
            failedSyncs: failedSyncs.count,
            averageSyncDuration: averageDuration,
            totalChangesSynced: totalChanges,
            totalConflicts: totalConflicts,
            conflictsResolved: conflictHistory.count,
            recentSyncs: Array(syncHistory.suffix(10)),
            recentConflicts: Array(conflictHistory.suffix(10))
        )
    }
}

public struct SyncDiagnosticsReport {
    public let totalSyncs: Int
    public let successfulSyncs: Int
    public let failedSyncs: Int
    public let averageSyncDuration: TimeInterval
    public let totalChangesSynced: Int
    public let totalConflicts: Int
    public let conflictsResolved: Int
    public let recentSyncs: [SyncDiagnostics.SyncEvent]
    public let recentConflicts: [SyncDiagnostics.ConflictEvent]
    
    public var successRate: Double {
        guard totalSyncs > 0 else { return 0 }
        return Double(successfulSyncs) / Double(totalSyncs)
    }
}