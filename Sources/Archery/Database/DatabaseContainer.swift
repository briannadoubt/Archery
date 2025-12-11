import Foundation
import GRDB

// MARK: - GRDB Container

/// DI container for GRDB database connections.
/// Wraps DatabaseQueue or DatabasePool for use with EnvContainer.
public final class PersistenceContainer: @unchecked Sendable {
    /// The underlying database writer (DatabaseQueue or DatabasePool)
    public let writer: any GRDB.DatabaseWriter

    /// Initialize with an existing PersistenceWriter
    public init(writer: any GRDB.DatabaseWriter) {
        self.writer = writer
    }

    /// Create an in-memory database (useful for tests and previews)
    public static func inMemory() throws -> PersistenceContainer {
        let queue = try DatabaseQueue()
        return PersistenceContainer(writer: queue)
    }

    /// Create a file-backed database using DatabaseQueue (single writer)
    public static func file(at url: URL) throws -> PersistenceContainer {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let queue = try DatabaseQueue(path: url.path)
        return PersistenceContainer(writer: queue)
    }

    /// Create a file-backed database using DatabasePool (concurrent readers)
    public static func pool(at url: URL) throws -> PersistenceContainer {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let pool = try DatabasePool(path: url.path)
        return PersistenceContainer(writer: pool)
    }

    /// Default database location in Application Support
    public static var defaultURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleId = Bundle.main.bundleIdentifier ?? "com.archery.app"
        return appSupport.appendingPathComponent(bundleId).appendingPathComponent("database.sqlite")
    }
}

// MARK: - EnvContainer Integration

public extension EnvContainer {
    /// Register a GRDB container for dependency injection
    func registerGRDB(_ container: PersistenceContainer) {
        register(container)
    }

    /// Resolve the registered GRDB container
    var grdb: PersistenceContainer? {
        resolve()
    }
}

// MARK: - Database Reader/Writer Convenience

public extension PersistenceContainer {
    /// Execute a read-only database operation
    func read<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        try await writer.read(block)
    }

    /// Execute a write database operation
    func write<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        try await writer.write(block)
    }
}
