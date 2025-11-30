import Foundation
import Combine

public protocol CacheKey: Hashable, Codable {
    var identifier: String { get }
}

public protocol Cacheable: Codable {
    associatedtype Key: CacheKey
    var key: Key { get }
    var lastModified: Date { get }
    var version: Int { get }
}

public enum ConflictResolution {
    case lastWriteWins
    case serverWins
    case clientWins
    case merge(MergeStrategy)
    case custom((any Cacheable, any Cacheable) -> any Cacheable)
}

public struct MergeStrategy {
    public let name: String
    public let merge: (any Cacheable, any Cacheable) -> any Cacheable
    
    public static let append = MergeStrategy(name: "append") { local, remote in
        remote
    }
    
    public static let preferNewer = MergeStrategy(name: "preferNewer") { local, remote in
        local.lastModified > remote.lastModified ? local : remote
    }
}

public actor OfflineCache<Item: Cacheable> {
    private var memoryCache: [Item.Key: Item] = [:]
    private var diskCache: DiskCache<Item>
    private let conflictPolicy: ConflictResolution
    private let maxMemoryItems: Int
    private let maxDiskSize: Int64
    
    public init(
        name: String,
        conflictPolicy: ConflictResolution = .lastWriteWins,
        maxMemoryItems: Int = 1000,
        maxDiskSize: Int64 = 100_000_000 // 100MB
    ) {
        self.conflictPolicy = conflictPolicy
        self.maxMemoryItems = maxMemoryItems
        self.maxDiskSize = maxDiskSize
        self.diskCache = DiskCache(name: name, maxSize: maxDiskSize)
    }
    
    public func get(_ key: Item.Key) async -> Item? {
        if let item = memoryCache[key] {
            return item
        }
        
        if let item = await diskCache.get(key) {
            await promoteToMemory(item)
            return item
        }
        
        return nil
    }
    
    public func set(_ item: Item) async {
        memoryCache[item.key] = item
        await diskCache.set(item)
        
        if memoryCache.count > maxMemoryItems {
            await evictFromMemory()
        }
    }
    
    public func merge(_ remote: Item) async -> Item {
        guard let local = await get(remote.key) else {
            await set(remote)
            return remote
        }
        
        let resolved = resolveConflict(local: local, remote: remote)
        await set(resolved)
        return resolved
    }
    
    public func remove(_ key: Item.Key) async {
        memoryCache.removeValue(forKey: key)
        await diskCache.remove(key)
    }
    
    public func clear() async {
        memoryCache.removeAll()
        await diskCache.clear()
    }
    
    public func getAllKeys() async -> [Item.Key] {
        await diskCache.getAllKeys()
    }
    
    public func getAll() async -> [Item] {
        await diskCache.getAll()
    }
    
    private func resolveConflict(local: Item, remote: Item) -> Item {
        switch conflictPolicy {
        case .lastWriteWins:
            return local.lastModified > remote.lastModified ? local : remote
        case .serverWins:
            return remote
        case .clientWins:
            return local
        case .merge(let strategy):
            return strategy.merge(local, remote) as! Item
        case .custom(let resolver):
            return resolver(local, remote) as! Item
        }
    }
    
    private func promoteToMemory(_ item: Item) async {
        memoryCache[item.key] = item
        
        if memoryCache.count > maxMemoryItems {
            await evictFromMemory()
        }
    }
    
    private func evictFromMemory() async {
        let sortedKeys = memoryCache.keys.sorted { key1, key2 in
            let item1 = memoryCache[key1]!
            let item2 = memoryCache[key2]!
            return item1.lastModified < item2.lastModified
        }
        
        let keysToRemove = sortedKeys.prefix(memoryCache.count / 4)
        for key in keysToRemove {
            memoryCache.removeValue(forKey: key)
        }
    }
}

public actor DiskCache<Item: Cacheable> {
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let maxSize: Int64
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    public init(name: String, maxSize: Int64) {
        self.maxSize = maxSize
        
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.cacheDirectory = documentsPath
            .appendingPathComponent("OfflineCache")
            .appendingPathComponent(name)
        
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    public func get(_ key: Item.Key) async -> Item? {
        let fileURL = cacheDirectory.appendingPathComponent("\(key.identifier).cache")
        
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        return try? decoder.decode(Item.self, from: data)
    }
    
    public func set(_ item: Item) async {
        let fileURL = cacheDirectory.appendingPathComponent("\(item.key.identifier).cache")
        
        guard let data = try? encoder.encode(item) else {
            return
        }
        
        try? data.write(to: fileURL)
        await enforceMaxSize()
    }
    
    public func remove(_ key: Item.Key) async {
        let fileURL = cacheDirectory.appendingPathComponent("\(key.identifier).cache")
        try? fileManager.removeItem(at: fileURL)
    }
    
    public func clear() async {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    public func getAllKeys() async -> [Item.Key] {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        
        return files.compactMap { url in
            let identifier = url.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: url),
                  let item = try? decoder.decode(Item.self, from: data) else {
                return nil
            }
            return item.key
        }
    }
    
    public func getAll() async -> [Item] {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        
        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let item = try? decoder.decode(Item.self, from: data) else {
                return nil
            }
            return item
        }
    }
    
    private func enforceMaxSize() async {
        var totalSize: Int64 = 0
        var files: [(URL, Date, Int64)] = []
        
        guard let urls = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return
        }
        
        for url in urls {
            if let attributes = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
               let size = attributes.fileSize,
               let date = attributes.contentModificationDate {
                files.append((url, date, Int64(size)))
                totalSize += Int64(size)
            }
        }
        
        if totalSize > maxSize {
            files.sort { $0.1 < $1.1 }
            
            for file in files {
                try? fileManager.removeItem(at: file.0)
                totalSize -= file.2
                
                if totalSize <= maxSize {
                    break
                }
            }
        }
    }
}