import Foundation
import GRDB

// MARK: - GRDB Container

/// DI container for GRDB database connections.
/// Wraps DatabaseQueue or DatabasePool for use with EnvContainer.
public final class PersistenceContainer: @unchecked Sendable {
    /// The underlying database writer (DatabaseQueue or DatabasePool)
    public let writer: any GRDB.DatabaseWriter

    /// Global current container for use by App Intents and other non-SwiftUI contexts.
    /// Set this at app startup after initializing your database.
    ///
    /// Example:
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     init() {
    ///         let container = try! PersistenceContainer.file(at: PersistenceContainer.defaultURL)
    ///         PersistenceContainer.current = container
    ///     }
    /// }
    /// ```
    ///
    /// Thread-safe via nonisolated(unsafe) - set once at app startup.
    public nonisolated(unsafe) static var current: PersistenceContainer?

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

// MARK: - App Database Protocol

import SwiftUI

/// Protocol for app database types that can be used with @AppShell.
///
/// Uses `@Observable` pattern (Swift 5.9+) instead of `ObservableObject`.
///
/// Your app's database class should conform to this protocol:
/// ```swift
/// @MainActor
/// @Observable
/// final class AppDatabase: AppDatabaseProtocol {
///     static let shared = AppDatabase()
///     private(set) var container: PersistenceContainer?
///     var isReady = false
///     var error: Error?
///
///     func setup() async { ... }
/// }
/// ```
@MainActor
public protocol AppDatabaseProtocol: AnyObject {
    /// The persistence container (nil until setup completes)
    var container: PersistenceContainer? { get }

    /// Whether the database is ready for use
    var isReady: Bool { get }

    /// Error from database setup, if any
    var error: Error? { get }

    /// Initialize and set up the database
    func setup() async
}

// MARK: - Auto-Migrating Protocol

/// Protocol for @Persistable types that have auto-generated migrations.
///
/// Types conforming to this protocol provide a `createTableMigration` that
/// creates their database table. The `@Persistable` macro automatically
/// generates this conformance.
///
/// Example:
/// ```swift
/// @Persistable(table: "tasks")
/// struct Task: Codable, FetchableRecord, PersistableRecord {
///     @PrimaryKey var id: String
///     var title: String
///     @Indexed var status: TaskStatus
/// }
/// // Generates: extension Task: AutoMigrating { ... }
/// ```
public protocol AutoMigrating {
    /// Migration that creates the table for this type
    static var createTableMigration: Migration { get }
}

// MARK: - Migration Registry

/// Registry of all AutoMigrating types for automatic database setup.
///
/// Types register themselves at app launch, and @AppShell uses this
/// registry to run all migrations automatically.
///
/// Usage:
/// ```swift
/// // At app startup (handled by @AppShell):
/// let migrations = MigrationRegistry.shared.allMigrations()
/// let runner = MigrationRunner(migrations)
/// try runner.run(on: container)
/// ```
@MainActor
public final class MigrationRegistry {
    public static let shared = MigrationRegistry()

    private var types: [any AutoMigrating.Type] = []
    private var customMigrations: [Migration] = []

    private init() {}

    /// Register an AutoMigrating type
    public func register<T: AutoMigrating>(_ type: T.Type) {
        // Avoid duplicate registration
        guard !types.contains(where: { $0 == type }) else { return }
        types.append(type)
    }

    /// Register a custom migration (for complex cases like views, triggers, etc.)
    public func registerCustom(_ migration: Migration) {
        customMigrations.append(migration)
    }

    /// Get all migrations in order (auto-generated first, then custom)
    public func allMigrations() -> [Migration] {
        let autoMigrations = types.map { $0.createTableMigration }
        return autoMigrations + customMigrations
    }

    /// Clear all registrations (useful for testing)
    public func reset() {
        types.removeAll()
        customMigrations.removeAll()
    }

    /// Number of registered types
    public var count: Int { types.count }
}
