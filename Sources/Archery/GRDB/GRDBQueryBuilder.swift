import Foundation
import GRDB

// MARK: - Query Request Protocol

/// Protocol for types that can produce a GRDB observation request
public protocol GRDBQueryRequest<Element>: Sendable {
    associatedtype Element: FetchableRecord & Sendable

    /// Create a ValueObservation for this request
    func makeObservation() -> ValueObservation<ValueReducers.Fetch<[Element]>>
}

/// Protocol for single-record query requests
public protocol GRDBSingleQueryRequest<Element>: Sendable {
    associatedtype Element: FetchableRecord & Sendable

    /// Create a ValueObservation for a single record
    func makeObservation() -> ValueObservation<ValueReducers.Fetch<Element?>>
}

/// Protocol for count query requests
public protocol GRDBCountQueryRequest: Sendable {
    /// Create a ValueObservation for count
    func makeObservation() -> ValueObservation<ValueReducers.Fetch<Int>>
}

// MARK: - Query Builder for Multiple Records

/// Type-safe query builder for observing multiple records
public struct GRDBQueryBuilder<Record: FetchableRecord & TableRecord & Sendable>: GRDBQueryRequest, Sendable {
    public typealias Element = Record

    private let request: QueryInterfaceRequest<Record>

    init(request: QueryInterfaceRequest<Record>) {
        self.request = request
    }

    /// Create a query for all records
    public static func all() -> GRDBQueryBuilder<Record> {
        GRDBQueryBuilder(request: Record.all())
    }

    /// Filter records using a predicate
    public func filter(_ predicate: some SQLSpecificExpressible) -> GRDBQueryBuilder<Record> {
        GRDBQueryBuilder(request: request.filter(predicate))
    }

    /// Order records by the given orderings
    public func order(_ orderings: any SQLOrderingTerm...) -> GRDBQueryBuilder<Record> {
        GRDBQueryBuilder(request: request.order(orderings))
    }

    /// Order records by a single column
    public func order(by column: Column, ascending: Bool = true) -> GRDBQueryBuilder<Record> {
        if ascending {
            return GRDBQueryBuilder(request: request.order(column))
        } else {
            return GRDBQueryBuilder(request: request.order(column.desc))
        }
    }

    /// Limit the number of records returned
    public func limit(_ count: Int, offset: Int? = nil) -> GRDBQueryBuilder<Record> {
        if let offset {
            return GRDBQueryBuilder(request: request.limit(count, offset: offset))
        } else {
            return GRDBQueryBuilder(request: request.limit(count))
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
}

// MARK: - Query Builder for Single Record

/// Type-safe query builder for observing a single record
public struct GRDBSingleQueryBuilder<Record: FetchableRecord & TableRecord & Sendable>: GRDBSingleQueryRequest, Sendable {
    public typealias Element = Record

    private let request: QueryInterfaceRequest<Record>

    init(request: QueryInterfaceRequest<Record>) {
        self.request = request
    }

    /// Find a record by its primary key
    public static func find<ID: DatabaseValueConvertible>(_ id: ID) -> GRDBSingleQueryBuilder<Record> {
        GRDBSingleQueryBuilder(request: Record.filter(key: id))
    }

    /// Find a record matching a predicate (returns first match)
    public static func first(where predicate: some SQLSpecificExpressible) -> GRDBSingleQueryBuilder<Record> {
        GRDBSingleQueryBuilder(request: Record.filter(predicate).limit(1))
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
public struct GRDBCountQueryBuilder<Record: FetchableRecord & TableRecord & Sendable>: GRDBCountQueryRequest, Sendable {
    private let request: QueryInterfaceRequest<Record>

    init(request: QueryInterfaceRequest<Record>) {
        self.request = request
    }

    /// Count all records
    public static func count() -> GRDBCountQueryBuilder<Record> {
        GRDBCountQueryBuilder(request: Record.all())
    }

    /// Filter records before counting
    public func filter(_ predicate: some SQLSpecificExpressible) -> GRDBCountQueryBuilder<Record> {
        GRDBCountQueryBuilder(request: request.filter(predicate))
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
    static func all() -> GRDBQueryBuilder<Self> {
        GRDBQueryBuilder.all()
    }

    /// Find a single record by ID
    static func find<ID: DatabaseValueConvertible>(_ id: ID) -> GRDBSingleQueryBuilder<Self> {
        GRDBSingleQueryBuilder.find(id)
    }

    /// Find the first record matching a predicate
    static func first(where predicate: some SQLSpecificExpressible) -> GRDBSingleQueryBuilder<Self> {
        GRDBSingleQueryBuilder.first(where: predicate)
    }

    /// Count all records of this type
    static func count() -> GRDBCountQueryBuilder<Self> {
        GRDBCountQueryBuilder.count()
    }
}
