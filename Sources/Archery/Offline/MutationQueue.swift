import Foundation
import Combine

public protocol Mutation: Codable, Identifiable, Sendable {
    var id: String { get }
    var timestamp: Date { get }
    var retryCount: Int { get set }
    var maxRetries: Int { get }
    
    func execute() async throws -> MutationResult
    func canRetry() -> Bool
}

public enum MutationResult: Sendable {
    case success(Data?)
    case failure(Error)
    case conflict(Data?)
    case retry
}

public enum MutationState: String, Codable, Sendable {
    case pending
    case inProgress
    case completed
    case failed
    case conflicted
}

public struct MutationRecord: Codable, Identifiable, Sendable {
    public let id: String
    public let mutationType: String
    public let payload: Data
    public var state: MutationState
    public var timestamp: Date
    public var retryCount: Int
    public var lastError: String?
    
    public init(mutation: any Mutation) throws {
        self.id = mutation.id
        self.mutationType = String(describing: type(of: mutation))
        self.payload = try JSONEncoder().encode(mutation)
        self.state = .pending
        self.timestamp = mutation.timestamp
        self.retryCount = mutation.retryCount
        self.lastError = nil
    }
}

@MainActor
@Observable
public final class MutationQueue {
    public private(set) var pendingMutations: [MutationRecord] = []
    public private(set) var isProcessing = false
    public private(set) var lastSyncDate: Date?
    public private(set) var failedMutations: [MutationRecord] = []
    
    private let persistence: MutationPersistence
    private let connectivity: ConnectivityMonitor
    @ObservationIgnored
    private nonisolated(unsafe) var processingTask: Task<Void, Never>?
    private var mutationHandlers: [String: @Sendable (Data) async throws -> MutationResult]
    private let syncInterval: TimeInterval
    
    public init(
        name: String = "default",
        connectivity: ConnectivityMonitor = .shared,
        syncInterval: TimeInterval = 30
    ) {
        self.persistence = MutationPersistence(name: name)
        self.connectivity = connectivity
        self.syncInterval = syncInterval
        self.mutationHandlers = [:]
        
        Task {
            await loadPendingMutations()
            startBackgroundSync()
        }
    }
    
    public func enqueue<M: Mutation>(_ mutation: M) async {
        guard let record = try? MutationRecord(mutation: mutation) else {
            return
        }
        
        pendingMutations.append(record)
        await persistence.save(record)
        
        if connectivity.isConnected {
            await processQueue()
        }
    }
    
    public func processQueue() async {
        guard !isProcessing else { return }
        guard connectivity.isConnected else { return }
        
        isProcessing = true
        defer { isProcessing = false }
        
        var processed: [String] = []
        var failed: [MutationRecord] = []
        
        for var record in pendingMutations {
            record.state = .inProgress
            await persistence.update(record)
            
            do {
                let result = try await executeMutation(record)
                
                switch result {
                case .success:
                    record.state = .completed
                    processed.append(record.id)
                    await persistence.remove(record.id)
                    
                case .failure(let error):
                    record.state = .failed
                    record.lastError = error.localizedDescription
                    record.retryCount += 1
                    
                    if record.retryCount < 3 {
                        record.state = .pending
                        await persistence.update(record)
                    } else {
                        failed.append(record)
                        await persistence.moveTo(failedQueue: record)
                    }
                    
                case .conflict:
                    record.state = .conflicted
                    failed.append(record)
                    await persistence.moveTo(failedQueue: record)
                    
                case .retry:
                    record.state = .pending
                    record.retryCount += 1
                    await persistence.update(record)
                }
            } catch {
                record.state = .failed
                record.lastError = error.localizedDescription
                record.retryCount += 1
                
                if record.retryCount < 3 {
                    record.state = .pending
                    await persistence.update(record)
                } else {
                    failed.append(record)
                    await persistence.moveTo(failedQueue: record)
                }
            }
        }
        
        pendingMutations.removeAll { processed.contains($0.id) }
        failedMutations.append(contentsOf: failed)
        lastSyncDate = Date()
    }
    
    public func retry(_ mutationId: String) async {
        guard let index = failedMutations.firstIndex(where: { $0.id == mutationId }) else {
            return
        }
        
        var record = failedMutations[index]
        record.state = .pending
        record.retryCount = 0
        
        failedMutations.remove(at: index)
        pendingMutations.append(record)
        
        await persistence.moveFromFailed(record)
        
        if connectivity.isConnected {
            await processQueue()
        }
    }
    
    public func retryAll() async {
        let toRetry = failedMutations
        failedMutations.removeAll()
        
        for var record in toRetry {
            record.state = .pending
            record.retryCount = 0
            pendingMutations.append(record)
            await persistence.moveFromFailed(record)
        }
        
        if connectivity.isConnected {
            await processQueue()
        }
    }
    
    public func clearFailed() async {
        failedMutations.removeAll()
        await persistence.clearFailedQueue()
    }

    public func clearAll() async {
        pendingMutations.removeAll()
        failedMutations.removeAll()
        await persistence.clearPendingQueue()
        await persistence.clearFailedQueue()
    }

    private func loadPendingMutations() async {
        pendingMutations = await persistence.loadPending()
        failedMutations = await persistence.loadFailed()
    }
    
    private func startBackgroundSync() {
        processingTask?.cancel()
        processingTask = Task { [weak self] in
            var lastConnected = false
            while let self = self, !Task.isCancelled {
                let isConnected = self.connectivity.isConnected
                // Process when connection becomes available
                if isConnected && !lastConnected && !self.pendingMutations.isEmpty {
                    await self.processQueue()
                }
                lastConnected = isConnected
                try? await Task.sleep(nanoseconds: 500_000_000) // Check every 0.5s
            }
        }

        Task { [weak self] in
            while let self = self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.syncInterval * 1_000_000_000))
                if self.connectivity.isConnected && !self.pendingMutations.isEmpty {
                    await self.processQueue()
                }
            }
        }
    }
    
    private func executeMutation(_ record: MutationRecord) async throws -> MutationResult {
        guard let handler = mutationHandlers[record.mutationType] else {
            throw MutationError.noHandler(type: record.mutationType)
        }
        
        return try await handler(record.payload)
    }
    
    public func registerHandler<M: Mutation>(
        for type: M.Type,
        handler: @escaping @Sendable (M) async throws -> MutationResult
    ) {
        let typeName = String(describing: type)
        mutationHandlers[typeName] = { data in
            let mutation = try JSONDecoder().decode(M.self, from: data)
            return try await handler(mutation)
        }
    }
    
    nonisolated deinit {
        processingTask?.cancel()
    }

    // MARK: - Test Helpers

    #if DEBUG
    /// Test helper to directly add a record to failed mutations
    public func _testAddFailed(_ record: MutationRecord) {
        failedMutations.append(record)
    }
    #endif
}

public actor MutationPersistence {
    private let fileManager = FileManager.default
    private let pendingDirectory: URL
    private let failedDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    public init(name: String) {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let baseDirectory = documentsPath.appendingPathComponent("MutationQueue").appendingPathComponent(name)
        
        self.pendingDirectory = baseDirectory.appendingPathComponent("pending")
        self.failedDirectory = baseDirectory.appendingPathComponent("failed")
        
        try? fileManager.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: failedDirectory, withIntermediateDirectories: true)
    }
    
    public func save(_ record: MutationRecord) async {
        let fileURL = pendingDirectory.appendingPathComponent("\(record.id).mutation")
        guard let data = try? encoder.encode(record) else { return }
        try? data.write(to: fileURL)
    }
    
    public func update(_ record: MutationRecord) async {
        await save(record)
    }
    
    public func remove(_ id: String) async {
        let fileURL = pendingDirectory.appendingPathComponent("\(id).mutation")
        try? fileManager.removeItem(at: fileURL)
    }
    
    public func moveTo(failedQueue record: MutationRecord) async {
        let sourceURL = pendingDirectory.appendingPathComponent("\(record.id).mutation")
        let destinationURL = failedDirectory.appendingPathComponent("\(record.id).mutation")
        
        guard let data = try? encoder.encode(record) else { return }
        try? data.write(to: destinationURL)
        try? fileManager.removeItem(at: sourceURL)
    }
    
    public func moveFromFailed(_ record: MutationRecord) async {
        let sourceURL = failedDirectory.appendingPathComponent("\(record.id).mutation")
        let destinationURL = pendingDirectory.appendingPathComponent("\(record.id).mutation")
        
        guard let data = try? encoder.encode(record) else { return }
        try? data.write(to: destinationURL)
        try? fileManager.removeItem(at: sourceURL)
    }
    
    public func loadPending() async -> [MutationRecord] {
        await loadFrom(directory: pendingDirectory)
    }
    
    public func loadFailed() async -> [MutationRecord] {
        await loadFrom(directory: failedDirectory)
    }
    
    public func clearFailedQueue() async {
        guard let files = try? fileManager.contentsOfDirectory(at: failedDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        for file in files {
            try? fileManager.removeItem(at: file)
        }
    }

    public func clearPendingQueue() async {
        guard let files = try? fileManager.contentsOfDirectory(at: pendingDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        for file in files {
            try? fileManager.removeItem(at: file)
        }
    }

    private func loadFrom(directory: URL) async -> [MutationRecord] {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        
        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(MutationRecord.self, from: data) else {
                return nil
            }
            return record
        }
    }
}

public enum MutationError: LocalizedError {
    case noHandler(type: String)
    case encodingFailed
    case decodingFailed
    
    public var errorDescription: String? {
        switch self {
        case .noHandler(let type):
            return "No handler registered for mutation type: \(type)"
        case .encodingFailed:
            return "Failed to encode mutation"
        case .decodingFailed:
            return "Failed to decode mutation"
        }
    }
}