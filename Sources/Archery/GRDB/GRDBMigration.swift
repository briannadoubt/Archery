import Foundation
import GRDB

// MARK: - Migration Definition

/// A single database migration step
public struct GRDBMigration: Sendable {
    /// Unique identifier for this migration (used for tracking applied migrations)
    public let id: String

    /// The migration function that modifies the database schema
    public let migrate: @Sendable (Database) throws -> Void

    public init(id: String, migrate: @escaping @Sendable (Database) throws -> Void) {
        self.id = id
        self.migrate = migrate
    }
}

// MARK: - Migration Runner

/// Runs migrations on a database
public struct GRDBMigrationRunner: Sendable {
    private let migrations: [GRDBMigration]

    public init(_ migrations: [GRDBMigration]) {
        self.migrations = migrations
    }

    /// Run all pending migrations on the database
    public func run(on container: GRDBContainer) throws {
        var migrator = DatabaseMigrator()

        for migration in migrations {
            migrator.registerMigration(migration.id) { db in
                try migration.migrate(db)
            }
        }

        try migrator.migrate(container.writer)
    }

    /// Run all pending migrations on a DatabaseWriter directly
    public func run(on writer: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()

        for migration in migrations {
            migrator.registerMigration(migration.id) { db in
                try migration.migrate(db)
            }
        }

        try migrator.migrate(writer)
    }

    /// Check if there are pending migrations
    public func hasPendingMigrations(on writer: any DatabaseWriter) throws -> Bool {
        var migrator = DatabaseMigrator()
        for migration in migrations {
            migrator.registerMigration(migration.id) { _ in }
        }
        return try writer.read { db in
            let applied = try migrator.appliedMigrations(db)
            // Has pending if our migration count exceeds applied count
            return migrations.count > applied.count
        }
    }
}

// MARK: - Migration Builder DSL

/// Builder for creating migrations with a fluent API
@resultBuilder
public struct GRDBMigrationBuilder {
    public static func buildBlock(_ migrations: GRDBMigration...) -> [GRDBMigration] {
        migrations
    }

    public static func buildArray(_ components: [[GRDBMigration]]) -> [GRDBMigration] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [GRDBMigration]?) -> [GRDBMigration] {
        component ?? []
    }

    public static func buildEither(first component: [GRDBMigration]) -> [GRDBMigration] {
        component
    }

    public static func buildEither(second component: [GRDBMigration]) -> [GRDBMigration] {
        component
    }
}

public extension GRDBMigrationRunner {
    /// Create a migration runner using a result builder
    init(@GRDBMigrationBuilder _ builder: () -> [GRDBMigration]) {
        self.migrations = builder()
    }
}

// MARK: - Common Migration Helpers

public extension GRDBMigration {
    /// Create a migration that creates a table for a Persistable type
    static func createTable<T: TableRecord>(
        id: String,
        for type: T.Type,
        body: @escaping @Sendable (TableDefinition) -> Void
    ) -> GRDBMigration {
        GRDBMigration(id: id) { db in
            try db.create(table: T.databaseTableName) { t in
                body(t)
            }
        }
    }

    /// Create a migration that adds a column to an existing table
    static func addColumn(
        id: String,
        table: String,
        column: String,
        type: Database.ColumnType,
        notNull: Bool = false
    ) -> GRDBMigration {
        GRDBMigration(id: id) { db in
            try db.alter(table: table) { t in
                let columnDef = t.add(column: column, type)
                if notNull {
                    _ = columnDef.notNull()
                }
            }
        }
    }

    /// Create a migration that adds a column with a default value
    static func addColumn(
        id: String,
        table: String,
        column: String,
        type: Database.ColumnType,
        notNull: Bool = false,
        defaultSQL: String
    ) -> GRDBMigration {
        GRDBMigration(id: id) { db in
            try db.alter(table: table) { t in
                let columnDef = t.add(column: column, type)
                if notNull {
                    _ = columnDef.notNull().defaults(sql: defaultSQL)
                } else {
                    _ = columnDef.defaults(sql: defaultSQL)
                }
            }
        }
    }

    /// Create a migration that creates an index
    static func createIndex(
        id: String,
        table: String,
        columns: [String],
        unique: Bool = false
    ) -> GRDBMigration {
        GRDBMigration(id: id) { db in
            try db.create(index: "\(table)_\(columns.joined(separator: "_"))_idx", on: table, columns: columns, unique: unique)
        }
    }

    /// Create a migration that drops a table
    static func dropTable(id: String, table: String) -> GRDBMigration {
        GRDBMigration(id: id) { db in
            try db.drop(table: table)
        }
    }

    /// Create a migration that runs raw SQL
    static func sql(id: String, _ sql: String) -> GRDBMigration {
        GRDBMigration(id: id) { db in
            try db.execute(sql: sql)
        }
    }
}
