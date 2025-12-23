import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - Schema Attribute Macros
// These are peer macros that serve as markers for @Persistable to inspect.
// They don't generate any code - @Persistable reads them during expansion.

/// Marks a property as the primary key for the database table.
/// If not specified, @Persistable assumes a property named "id" is the primary key.
public struct PrimaryKeyMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // No-op - @Persistable inspects this attribute directly
        []
    }
}

/// Marks a property to have a database index created for faster queries.
/// Use on columns frequently used in WHERE clauses or sorting.
public struct IndexedMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

/// Marks a property as having a unique constraint in the database.
/// Optionally takes a group name for composite unique constraints.
public struct UniqueMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

/// Marks a property as a foreign key reference to another @Persistable type.
/// The referenced table name is inferred from the type's databaseTableName.
public struct ForeignKeyMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

/// Marks a Date property to be auto-set to the current date on record insertion.
/// The property should be of type Date (not optional).
public struct CreatedAtMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

/// Marks a Date property to be auto-updated to the current date on record update.
/// The property should be of type Date (not optional).
public struct UpdatedAtMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

/// Marks a property as transient - it will not be persisted to the database.
/// The property will be excluded from the Columns enum and migration generation.
/// Use for computed caches, selection state, or other non-persistent data.
///
/// Named `NotPersisted` to avoid conflict with SwiftData's `@Transient` macro.
public struct NotPersistedMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

/// Marks a property to have a default value in the database schema.
/// This ensures new rows have this value when the column is not specified.
public struct DefaultMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

/// Explicitly sets the SQLite column type for a property.
/// Use this for enums or custom types where the macro can't infer the correct type.
///
/// Usage:
/// ```swift
/// @ColumnType(.integer)
/// var priority: TaskPriority  // Int-backed enum stored as INTEGER
///
/// @ColumnType(.text)
/// var status: TaskStatus      // String-backed enum stored as TEXT
/// ```
///
/// Available types: `.text`, `.integer`, `.double`, `.blob`, `.datetime`
public struct ColumnTypeMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
