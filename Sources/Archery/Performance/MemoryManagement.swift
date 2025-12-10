import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Memory Warning Manager

@MainActor
public final class MemoryWarningManager: ObservableObject {
    public static let shared = MemoryWarningManager()
    
    @Published public private(set) var currentPressure: MemoryPressure = .normal
    @Published public private(set) var memoryUsage: MemoryUsage = .init()
    
    private var cancellables = Set<AnyCancellable>()
    private let loadShedders: NSHashTable<AnyObject> = .weakObjects()
    private let queue = DispatchQueue(label: "com.archery.memory")
    
    public enum MemoryPressure: Int, Comparable, Sendable {
        case normal = 0
        case warning = 1
        case critical = 2

        public static func < (lhs: MemoryPressure, rhs: MemoryPressure) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    public struct MemoryUsage: Sendable {
        public let used: Int64 // bytes
        public let available: Int64
        public let total: Int64
        
        public var usedMB: Double { Double(used) / 1024 / 1024 }
        public var availableMB: Double { Double(available) / 1024 / 1024 }
        public var totalMB: Double { Double(total) / 1024 / 1024 }
        public var percentUsed: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
        
        init(used: Int64 = 0, available: Int64 = 0, total: Int64 = 0) {
            self.used = used
            self.available = available
            self.total = total
        }
    }
    
    private init() {
        setupMemoryWarningObservers()
        startMemoryMonitoring()
    }
    
    // MARK: - Memory Warning Observers
    
    private func setupMemoryWarningObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)
        #endif
    }
    
    private func handleMemoryWarning() {
        queue.async { [weak self] in
            self?.currentPressure = .warning
            self?.triggerLoadShedding(level: .warning)
            
            // Auto-recover after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                if self?.currentPressure == .warning {
                    self?.currentPressure = .normal
                }
            }
        }
    }
    
    // MARK: - Memory Monitoring
    
    private func startMemoryMonitoring() {
        Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateMemoryUsage()
            }
            .store(in: &cancellables)
    }
    
    private func updateMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let used = Int64(info.resident_size)
            let total = Int64(ProcessInfo.processInfo.physicalMemory)
            let available = total - used
            
            memoryUsage = MemoryUsage(
                used: used,
                available: available,
                total: total
            )
            
            // Update pressure based on usage
            let percentUsed = memoryUsage.percentUsed
            if percentUsed > 90 {
                currentPressure = .critical
            } else if percentUsed > 75 {
                currentPressure = .warning
            } else {
                currentPressure = .normal
            }
        }
    }
    
    // MARK: - Load Shedding
    
    public func register(_ loadShedder: LoadShedding) {
        queue.async { [weak self] in
            self?.loadShedders.add(loadShedder as AnyObject)
        }
    }
    
    private func triggerLoadShedding(level: MemoryPressure) {
        let shedders = loadShedders.allObjects.compactMap { $0 as? LoadShedding }
        for shedder in shedders {
            shedder.shed(level: level)
        }
    }
    
    public func requestLoadShedding(level: MemoryPressure = .warning) {
        triggerLoadShedding(level: level)
    }
}

// MARK: - Load Shedding Protocol

@MainActor
public protocol LoadShedding: AnyObject {
    func shed(level: MemoryWarningManager.MemoryPressure)
}

// MARK: - Cache Manager with Load Shedding

@MainActor
public final class CacheManager: LoadShedding {
    private var caches: [String: Any] = [:]
    private let maxSize: Int
    private var currentSize: Int = 0

    public init(maxSizeMB: Int = 50) {
        self.maxSize = maxSizeMB * 1024 * 1024
        MemoryWarningManager.shared.register(self)
    }
    
    public func set<T>(_ value: T, for key: String) {
        let size = MemoryLayout<T>.size
        if currentSize + size > maxSize {
            evictLRU()
        }

        caches[key] = CacheEntry(value: value, size: size)
        currentSize += size
    }

    public func get<T>(_ key: String, as type: T.Type) -> T? {
        guard let entry = caches[key] as? CacheEntry<T> else { return nil }
        entry.lastAccessed = Date()
        return entry.value
    }

    public func shed(level: MemoryWarningManager.MemoryPressure) {
        switch level {
        case .normal:
            return
        case .warning:
            // Remove 50% of cache
            let target = currentSize / 2
            evictToSize(target)
        case .critical:
            // Clear all caches
            caches.removeAll()
            currentSize = 0
        }
    }
    
    private func evictLRU() {
        // Simplified LRU eviction
        if let oldest = caches.keys.first {
            if let entry = caches[oldest] as? AnyCacheEntry {
                currentSize -= entry.size
            }
            caches.removeValue(forKey: oldest)
        }
    }
    
    private func evictToSize(_ targetSize: Int) {
        while currentSize > targetSize && !caches.isEmpty {
            evictLRU()
        }
    }
    
    private class AnyCacheEntry {
        let size: Int
        var lastAccessed: Date
        
        init(size: Int) {
            self.size = size
            self.lastAccessed = Date()
        }
    }
    
    private final class CacheEntry<T>: AnyCacheEntry {
        let value: T
        
        init(value: T, size: Int) {
            self.value = value
            super.init(size: size)
        }
    }
}

// MARK: - Image Cache with Load Shedding

#if canImport(UIKit)
@MainActor
public final class ImageCache: LoadShedding {
    private let cache = NSCache<NSString, UIImage>()
    private let decoder = ImageDecoder()

    public init(countLimit: Int = 100, totalCostLimit: Int = 50 * 1024 * 1024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
        MemoryWarningManager.shared.register(self)
    }
    
    public func image(for url: URL) async throws -> UIImage {
        let key = url.absoluteString as NSString
        
        if let cached = cache.object(forKey: key) {
            return cached
        }
        
        let image = try await decoder.decode(from: url)
        cache.setObject(image, forKey: key, cost: image.cost)
        return image
    }
    
    public func shed(level: MemoryWarningManager.MemoryPressure) {
        switch level {
        case .normal:
            return
        case .warning:
            cache.totalCostLimit = cache.totalCostLimit / 2
        case .critical:
            cache.removeAllObjects()
        }
    }
    
    private struct ImageDecoder {
        func decode(from url: URL) async throws -> UIImage {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                throw ImageError.decodingFailed
            }
            return image
        }
    }
    
    enum ImageError: Error {
        case decodingFailed
    }
}

extension UIImage {
    var cost: Int {
        guard let cgImage = cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
#endif

// MARK: - Repository with Load Shedding

@MainActor
public class LoadSheddingRepository: LoadShedding {
    private var inflightRequestKeys: Set<String> = []
    private var cancellationHandlers: [String: () -> Void] = [:]

    public init() {
        MemoryWarningManager.shared.register(self)
    }

    public func shed(level: MemoryWarningManager.MemoryPressure) {
        switch level {
        case .normal:
            return
        case .warning:
            // Cancel non-critical requests (half of them)
            cancelNonCriticalRequests()
        case .critical:
            // Cancel all requests
            cancelAllRequests()
        }
    }

    private func cancelNonCriticalRequests() {
        // Implementation would identify and cancel non-critical requests
        let toCancelCount = cancellationHandlers.count / 2
        var cancelled = 0
        for (key, handler) in cancellationHandlers {
            if cancelled >= toCancelCount { break }
            handler()
            cancellationHandlers.removeValue(forKey: key)
            inflightRequestKeys.remove(key)
            cancelled += 1
        }
    }

    private func cancelAllRequests() {
        for (_, handler) in cancellationHandlers {
            handler()
        }
        cancellationHandlers.removeAll()
        inflightRequestKeys.removeAll()
    }

    internal func trackRequest<T: Sendable>(
        key: String,
        critical: Bool = false,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        registerKey(key)

        return try await withTaskCancellationHandler {
            defer { unregisterKey(key) }
            return try await operation()
        } onCancel: {
            // Cancellation is handled by Swift concurrency
        }
    }

    private func registerKey(_ key: String) {
        inflightRequestKeys.insert(key)
    }

    private func unregisterKey(_ key: String) {
        inflightRequestKeys.remove(key)
        cancellationHandlers.removeValue(forKey: key)
    }
}

// MARK: - ViewModel with Load Shedding

@MainActor
open class LoadSheddingViewModel: ObservableObject, LoadShedding {
    private var loadTask: Task<Void, Never>?
    private var debounceTimers: [String: Timer] = [:]

    public init() {
        MemoryWarningManager.shared.register(self)
    }

    public func shed(level: MemoryWarningManager.MemoryPressure) {
        switch level {
        case .normal:
            return
        case .warning:
            // Cancel debounced operations
            cancelDebouncedOperations()
        case .critical:
            // Cancel all async operations
            cancelAllOperations()
        }
    }

    private func cancelDebouncedOperations() {
        for (_, timer) in debounceTimers {
            timer.invalidate()
        }
        debounceTimers.removeAll()
    }

    private func cancelAllOperations() {
        loadTask?.cancel()
        loadTask = nil
        cancelDebouncedOperations()
    }

    internal func trackLoad(_ operation: @escaping @Sendable () async -> Void) {
        loadTask?.cancel()
        loadTask = Task {
            await operation()
        }
    }
}