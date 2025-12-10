import XCTest
import Combine
@testable import Archery

struct TestCacheKey: CacheKey {
    let identifier: String
}

struct TestCacheItem: Cacheable {
    let key: TestCacheKey
    let value: String
    let lastModified: Date
    let version: Int
    
    init(id: String, value: String, lastModified: Date = Date(), version: Int = 1) {
        self.key = TestCacheKey(identifier: id)
        self.value = value
        self.lastModified = lastModified
        self.version = version
    }
}

struct TestMutation: Mutation {
    let id: String
    let timestamp: Date
    var retryCount: Int
    let maxRetries: Int
    let shouldFail: Bool
    
    init(
        id: String = UUID().uuidString,
        shouldFail: Bool = false,
        retryCount: Int = 0,
        maxRetries: Int = 3
    ) {
        self.id = id
        self.timestamp = Date()
        self.retryCount = retryCount
        self.maxRetries = maxRetries
        self.shouldFail = shouldFail
    }
    
    func execute() async throws -> MutationResult {
        if shouldFail {
            return .failure(TestError.executionFailed)
        }
        return .success("completed".data(using: .utf8))
    }
    
    func canRetry() -> Bool {
        retryCount < maxRetries
    }
}

enum TestError: Error {
    case executionFailed
}

final class OfflineCacheTests: XCTestCase {
    var cache: OfflineCache<TestCacheItem>!
    
    override func setUp() async throws {
        cache = OfflineCache(name: "test_cache")
        await cache.clear()
    }
    
    override func tearDown() async throws {
        await cache.clear()
    }
    
    func testSetAndGet() async {
        let item = TestCacheItem(id: "1", value: "test")
        await cache.set(item)
        
        let retrieved = await cache.get(TestCacheKey(identifier: "1"))
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.value, "test")
    }
    
    func testRemove() async {
        let item = TestCacheItem(id: "1", value: "test")
        await cache.set(item)
        
        await cache.remove(TestCacheKey(identifier: "1"))
        let retrieved = await cache.get(TestCacheKey(identifier: "1"))
        XCTAssertNil(retrieved)
    }
    
    func testGetAllKeys() async {
        let items = [
            TestCacheItem(id: "1", value: "one"),
            TestCacheItem(id: "2", value: "two"),
            TestCacheItem(id: "3", value: "three")
        ]
        
        for item in items {
            await cache.set(item)
        }
        
        let keys = await cache.getAllKeys()
        XCTAssertEqual(keys.count, 3)
    }
    
    func testLastWriteWinsConflictResolution() async {
        let cache = OfflineCache<TestCacheItem>(
            name: "lww_cache",
            conflictPolicy: .lastWriteWins
        )
        
        let older = TestCacheItem(
            id: "1",
            value: "old",
            lastModified: Date().addingTimeInterval(-60)
        )
        await cache.set(older)
        
        let newer = TestCacheItem(
            id: "1",
            value: "new",
            lastModified: Date()
        )
        let resolved = await cache.merge(newer)
        
        XCTAssertEqual(resolved.value, "new")
    }
    
    func testServerWinsConflictResolution() async {
        let cache = OfflineCache<TestCacheItem>(
            name: "server_cache",
            conflictPolicy: .serverWins
        )
        
        let local = TestCacheItem(
            id: "1",
            value: "local",
            lastModified: Date()
        )
        await cache.set(local)
        
        let remote = TestCacheItem(
            id: "1",
            value: "remote",
            lastModified: Date().addingTimeInterval(-60)
        )
        let resolved = await cache.merge(remote)
        
        XCTAssertEqual(resolved.value, "remote")
    }
    
    func testMemoryEviction() async {
        let cache = OfflineCache<TestCacheItem>(
            name: "eviction_cache",
            maxMemoryItems: 5
        )
        
        for i in 0..<10 {
            let item = TestCacheItem(id: "\(i)", value: "item\(i)")
            await cache.set(item)
        }
        
        let allItems = await cache.getAll()
        XCTAssertEqual(allItems.count, 10)
    }
}

final class MutationQueueTests: XCTestCase {
    var queue: MutationQueue!
    var connectivity: ConnectivityMonitor!
    
    @MainActor
    override func setUp() async throws {
        connectivity = ConnectivityMonitor.shared
        queue = MutationQueue(name: "test_queue", connectivity: connectivity)
    }
    
    @MainActor
    override func tearDown() async throws {
        await queue.clearFailed()
    }
    
    @MainActor
    func testEnqueueMutation() async {
        let mutation = TestMutation()
        await queue.enqueue(mutation)
        
        XCTAssertEqual(queue.pendingMutations.count, 1)
    }
    
    @MainActor
    func testProcessQueueSuccess() async {
        queue.registerHandler(for: TestMutation.self) { mutation in
            if mutation.shouldFail {
                return .failure(TestError.executionFailed)
            }
            return .success("completed".data(using: .utf8))
        }

        let mutation = TestMutation(shouldFail: false)
        await queue.enqueue(mutation)
        
        await queue.processQueue()
        
        XCTAssertEqual(queue.pendingMutations.count, 0)
        XCTAssertEqual(queue.failedMutations.count, 0)
    }
    
    @MainActor
    func testProcessQueueFailure() async {
        queue.registerHandler(for: TestMutation.self) { mutation in
            return .failure(TestError.executionFailed)
        }
        
        let mutation = TestMutation()
        await queue.enqueue(mutation)
        
        await queue.processQueue()
        
        XCTAssertTrue(queue.pendingMutations.count > 0 || queue.failedMutations.count > 0)
    }
    
    @MainActor
    func testRetryMutation() async {
        queue.registerHandler(for: TestMutation.self) { mutation in
            if mutation.retryCount == 0 {
                return .failure(TestError.executionFailed)
            }
            return .success("completed".data(using: .utf8))
        }

        var mutation = TestMutation()
        mutation.retryCount = 3
        
        let record = try! MutationRecord(mutation: mutation)
        queue._testAddFailed(record)
        
        await queue.retry(record.id)
        
        XCTAssertTrue(queue.pendingMutations.contains { $0.id == record.id })
    }
    
    @MainActor
    func testRetryAll() async {
        let mutations = [
            TestMutation(id: "1"),
            TestMutation(id: "2"),
            TestMutation(id: "3")
        ]
        
        for mutation in mutations {
            let record = try! MutationRecord(mutation: mutation)
            queue._testAddFailed(record)
        }
        
        await queue.retryAll()
        
        XCTAssertEqual(queue.failedMutations.count, 0)
        XCTAssertEqual(queue.pendingMutations.count, 3)
    }
}

final class ConnectivityMonitorTests: XCTestCase {
    @MainActor
    func testInitialState() {
        let monitor = ConnectivityMonitor.shared
        XCTAssertNotNil(monitor)
    }
    
    @MainActor
    func testConnectionHistory() {
        let monitor = ConnectivityMonitor.shared
        let history = monitor.getConnectionHistory()
        XCTAssertNotNil(history)
    }
    
    @MainActor
    func testAverageUptime() {
        let monitor = ConnectivityMonitor.shared
        let uptime = monitor.getAverageUptime(over: 3600)
        XCTAssertGreaterThanOrEqual(uptime, 0)
        XCTAssertLessThanOrEqual(uptime, 1)
    }
}

final class SyncCoordinatorTests: XCTestCase {
    var coordinator: SyncCoordinator!
    var mutationQueue: MutationQueue!
    
    @MainActor
    override func setUp() async throws {
        mutationQueue = MutationQueue(name: "test_sync")
        coordinator = SyncCoordinator(mutationQueue: mutationQueue)
    }
    
    @MainActor
    func testSyncStateTransitions() async {
        XCTAssertEqual(coordinator.syncState, .idle)
        
        await coordinator.sync()
        
        XCTAssertTrue(
            coordinator.syncState == .idle ||
            coordinator.syncState == .offline
        )
    }
    
    @MainActor
    func testConflictResolution() async {
        let conflict = ConflictRecord(
            key: "test",
            localValue: "local",
            remoteValue: "remote"
        )
        
        coordinator._testAddConflict(conflict)
        
        await coordinator.resolveConflict(conflict.id, resolution: .lastWriteWins)
        
        XCTAssertFalse(coordinator.conflicts.contains { $0.id == conflict.id })
    }
    
    @MainActor
    func testSyncMetrics() async {
        await coordinator.sync()
        
        XCTAssertGreaterThan(coordinator.metrics.syncAttempts, 0)
    }
    
    @MainActor
    func testDiagnosticsReport() async {
        await coordinator.sync()
        
        let diagnostics = coordinator.getDiagnostics()
        let report = await diagnostics.generateReport()
        
        XCTAssertGreaterThanOrEqual(report.totalSyncs, 0)
        XCTAssertGreaterThanOrEqual(report.successRate, 0)
        XCTAssertLessThanOrEqual(report.successRate, 1)
    }
}

final class SyncDiagnosticsTests: XCTestCase {
    func testRecordSyncEvent() async {
        let diagnostics = SyncDiagnostics()
        
        await diagnostics.recordSync(
            success: true,
            duration: 1.5,
            changesSync: 10,
            conflicts: 2
        )
        
        let history = await diagnostics.getSyncHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertTrue(history[0].success)
        XCTAssertEqual(history[0].changesSynced, 10)
    }
    
    func testRecordConflictResolution() async {
        let diagnostics = SyncDiagnostics()

        await diagnostics.recordConflictResolution(
            key: "test",
            resolution: .lastWriteWins
        )

        let history = await diagnostics.getConflictHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].key, "test")
    }
    
    func testGenerateReport() async {
        let diagnostics = SyncDiagnostics()
        
        for i in 0..<5 {
            await diagnostics.recordSync(
                success: i % 2 == 0,
                duration: Double(i),
                changesSync: i * 2,
                conflicts: i % 3 == 0 ? 1 : 0
            )
        }
        
        let report = await diagnostics.generateReport()
        
        XCTAssertEqual(report.totalSyncs, 5)
        XCTAssertEqual(report.successfulSyncs, 3)
        XCTAssertEqual(report.failedSyncs, 2)
        XCTAssertEqual(report.successRate, 0.6)
    }
}