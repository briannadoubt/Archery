import Foundation
import GRDB

// MARK: - GRDB Container

/// DI container for GRDB database connections.
/// Wraps DatabaseQueue or DatabasePool for use with EnvContainer.
public final class GRDBContainer: @unchecked Sendable {
    /// The underlying database writer (DatabaseQueue or DatabasePool)
    public let writer: any DatabaseWriter

    /// Initialize with an existing DatabaseWriter
    public init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    /// Create an in-memory database (useful for tests and previews)
    public static func inMemory() throws -> GRDBContainer {
        let queue = try DatabaseQueue()
        return GRDBContainer(writer: queue)
    }

    /// Create a file-backed database using DatabaseQueue (single writer)
    public static func file(at url: URL) throws -> GRDBContainer {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let queue = try DatabaseQueue(path: url.path)
        return GRDBContainer(writer: queue)
    }

    /// Create a file-backed database using DatabasePool (concurrent readers)
    public static func pool(at url: URL) throws -> GRDBContainer {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let pool = try DatabasePool(path: url.path)
        return GRDBContainer(writer: pool)
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
    func registerGRDB(_ container: GRDBContainer) {
        register(container)
    }

    /// Resolve the registered GRDB container
    var grdb: GRDBContainer? {
        resolve()
    }
}

// MARK: - Database Reader/Writer Convenience

public extension GRDBContainer {
    /// Execute a read-only database operation
    func read<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        try await writer.read(block)
    }

    /// Execute a write database operation
    func write<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        try await writer.write(block)
    }
}
