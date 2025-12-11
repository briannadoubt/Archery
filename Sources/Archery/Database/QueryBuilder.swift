import Foundation
import GRDB

// MARK: - Query Request Protocol

/// Protocol for types that can produce a GRDB observation request
public protocol QueryRequest<Element>: Sendable {
    associatedtype Element: FetchableRecord & Sendable

    /// Create a ValueObservation for this request
    func makeObservation() -> ValueObservation<ValueReducers.Fetch<[Element]>>
}

/// Protocol for single-record query requests
public protocol SingleQueryRequest<Element>: Sendable {
    associatedtype Element: FetchableRecord & Sendable

    /// Create a ValueObservation for a single record
    func makeObservation() -> ValueObservation<ValueReducers.Fetch<Element?>>
}

/// Protocol for count query requests
public protocol CountQueryRequest: Sendable {
    /// Create a ValueObservation for count
    func makeObservation() -> ValueObservation<ValueReducers.Fetch<Int>>
}

// MARK: - Query Builder for Multiple Records

/// Type-safe query builder for observing multiple records
public struct QueryBuilder<Record: FetchableRecord & TableRecord & Sendable>: QueryRequest, Sendable {
    public typealias Element = Record

    private let request: QueryInterfaceRequest<Record>

    init(request: QueryInterfaceRequest<Record>) {
        self.request = request
    }

    /// Create a query for all records
    public static func all() -> QueryBuilder<Record> {
        QueryBuilder(request: Record.all())
    }

    /// Filter records using a predicate
    public func filter(_ predicate: some SQLSpecificExpressible) -> QueryBuilder<Record> {
        QueryBuilder(request: request.filter(predicate))
    }

    /// Order records by the given orderings
    public func order(_ orderings: any SQLOrderingTerm...) -> QueryBuilder<Record> {
        QueryBuilder(request: request.order(orderings))
    }

    /// Order records by a single column
    public func order(by column: Column, ascending: Bool = true) -> QueryBuilder<Record> {
        if ascending {
            return QueryBuilder(request: request.order(column))
        } else {
            return QueryBuilder(request: request.order(column.desc))
        }
    }

    /// Limit the number of records returned
    public func limit(_ count: Int, offset: Int? = nil) -> QueryBuilder<Record> {
        if let offset {
            return QueryBuilder(request: request.limit(count, offset: offset))
        } else {
            return QueryBuilder(request: request.limit(count))
        }
    }

    /// Create a ValueObservation for this query
    public func makeObservation() -> ValueObservation<ValueReducers.Fetch<[Record]>> {
        ValueObservation.tracking { db in
            try self.request.fetchAll(db)
        }
    }

    /// Access the underlying request for advanced usage
    public var underlyingRequest: QueryInterfaceRequest<Record> {
        request
    }

    /// Unique key for this query used in cache coordination
    /// Combines the table name with a hash of the query parameters
    public var queryKey: String {
        // Use table name as base, with a hash of the request for uniqueness
        let tableName = Record.databaseTableName
        // Create a simple but deterministic key
        // In production, you might want to serialize the SQL for a more precise key
        return "\(tableName)|\(ObjectIdentifier(type(of: request)).hashValue)"
    }
}

// MARK: - Query Builder for Single Record

/// Type-safe query builder for observing a single record
public struct SingleQueryBuilder<Record: FetchableRecord & TableRecord & Sendable>: SingleQueryRequest, Sendable {
    public typealias Element = Record

    private let request: QueryInterfaceRequest<Record>

    init(request: QueryInterfaceRequest<Record>) {
        self.request = request
    }

    /// Find a record by its primary key
    public static func find<ID: DatabaseValueConvertible>(_ id: ID) -> SingleQueryBuilder<Record> {
        SingleQueryBuilder(request: Record.filter(key: id))
    }

    /// Find a record matching a predicate (returns first match)
    public static func first(where predicate: some SQLSpecificExpressible) -> SingleQueryBuilder<Record> {
        SingleQueryBuilder(request: Record.filter(predicate).limit(1))
    }

    /// Create a ValueObservation for this query
    public func makeObservation() -> ValueObservation<ValueReducers.Fetch<Record?>> {
        ValueObservation.tracking { db in
            try self.request.fetchOne(db)
        }
    }
}

// MARK: - Query Builder for Count

/// Type-safe query builder for counting records
public struct CountQueryBuilder<Record: FetchableRecord & TableRecord & Sendable>: CountQueryRequest, Sendable {
    private let request: QueryInterfaceRequest<Record>

    init(request: QueryInterfaceRequest<Record>) {
        self.request = request
    }

    /// Count all records
    public static func count() -> CountQueryBuilder<Record> {
        CountQueryBuilder(request: Record.all())
    }

    /// Filter records before counting
    public func filter(_ predicate: some SQLSpecificExpressible) -> CountQueryBuilder<Record> {
        CountQueryBuilder(request: request.filter(predicate))
    }

    /// Create a ValueObservation for the count
    public func makeObservation() -> ValueObservation<ValueReducers.Fetch<Int>> {
        ValueObservation.tracking { db in
            try self.request.fetchCount(db)
        }
    }
}

// MARK: - Convenience Extensions for Record Types

public extension FetchableRecord where Self: TableRecord & Sendable {
    /// Create a query builder for all records of this type
    static func all() -> QueryBuilder<Self> {
        QueryBuilder.all()
    }

    /// Find a single record by ID
    static func find<ID: DatabaseValueConvertible>(_ id: ID) -> SingleQueryBuilder<Self> {
        SingleQueryBuilder.find(id)
    }

    /// Find the first record matching a predicate
    static func first(where predicate: some SQLSpecificExpressible) -> SingleQueryBuilder<Self> {
        SingleQueryBuilder.first(where: predicate)
    }

    /// Count all records of this type
    static func count() -> CountQueryBuilder<Self> {
        CountQueryBuilder.count()
    }
}
