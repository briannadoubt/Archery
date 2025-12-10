import Foundation
import GRDB

// MARK: - GRDB Error Types

/// Normalized error type for GRDB operations
public enum GRDBError: Error, Equatable, Sendable {
    case notFound
    case constraintViolation(String)
    case migrationFailed(String)
    case connectionFailed(String)
    case queryFailed(String)
    case encodingFailed(String)
    case decodingFailed(String)
    case unknown(String)
}

extension GRDBError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "Record not found"
        case .constraintViolation(let message):
            return "Constraint violation: \(message)"
        case .migrationFailed(let message):
            return "Migration failed: \(message)"
        case .connectionFailed(let message):
            return "Database connection failed: \(message)"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .encodingFailed(let message):
            return "Encoding failed: \(message)"
        case .decodingFailed(let message):
            return "Decoding failed: \(message)"
        case .unknown(let message):
            return "Unknown database error: \(message)"
        }
    }
}

// MARK: - Error Normalization

/// Normalize any error into a GRDBError
public func normalizeGRDBError(_ error: Error) -> GRDBError {
    if let grdbError = error as? GRDBError {
        return grdbError
    }

    if let databaseError = error as? DatabaseError {
        switch databaseError.resultCode {
        case .SQLITE_CONSTRAINT,
             .SQLITE_CONSTRAINT_CHECK,
             .SQLITE_CONSTRAINT_FOREIGNKEY,
             .SQLITE_CONSTRAINT_NOTNULL,
             .SQLITE_CONSTRAINT_PRIMARYKEY,
             .SQLITE_CONSTRAINT_UNIQUE:
            return .constraintViolation(databaseError.message ?? "Constraint violation")

        case .SQLITE_NOTFOUND:
            return .notFound

        case .SQLITE_CANTOPEN,
             .SQLITE_READONLY,
             .SQLITE_IOERR:
            return .connectionFailed(databaseError.message ?? "Connection error")

        default:
            return .queryFailed(databaseError.message ?? "Query failed with code \(databaseError.resultCode.rawValue)")
        }
    }

    if let decodingError = error as? DecodingError {
        return .decodingFailed(decodingError.localizedDescription)
    }

    if let encodingError = error as? EncodingError {
        return .encodingFailed(encodingError.localizedDescription)
    }

    return .unknown(error.localizedDescription)
}

// MARK: - Error Context

/// Wrapper that adds context to GRDB errors
public struct GRDBSourceError: Error, Sendable {
    public let function: String
    public let file: String
    public let line: Int
    public let underlying: GRDBError

    public init(
        _ underlying: GRDBError,
        function: String = #function,
        file: String = #file,
        line: Int = #line
    ) {
        self.function = function
        self.file = file
        self.line = line
        self.underlying = underlying
    }
}

extension GRDBSourceError: LocalizedError {
    public var errorDescription: String? {
        "\(underlying.errorDescription ?? "Unknown error") at \(function) (\(file):\(line))"
    }
}

/// Wrap and normalize an error with source context
public func normalizeGRDBError(
    _ error: Error,
    function: String = #function,
    file: String = #file,
    line: Int = #line
) -> GRDBSourceError {
    GRDBSourceError(normalizeGRDBError(error), function: function, file: file, line: line)
}
