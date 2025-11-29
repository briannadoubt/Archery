import Foundation

/// Retry configuration used by generated API clients.
public struct APIRetryPolicy: Sendable {
    public let maxRetries: Int
    public let baseDelay: Duration
    public let multiplier: Double
    public let jitter: Duration
    public let retryPredicate: @Sendable (Error) -> Bool

    public init(
        maxRetries: Int = 2,
        baseDelay: Duration = .milliseconds(150),
        multiplier: Double = 2.0,
        jitter: Duration = .milliseconds(50),
        shouldRetry: @escaping @Sendable (Error) -> Bool = APIRetryPolicy.defaultShouldRetry
    ) {
        self.maxRetries = max(0, maxRetries)
        self.baseDelay = baseDelay
        self.multiplier = multiplier
        self.jitter = jitter
        self.retryPredicate = shouldRetry
    }

    public func delay(for attempt: Int) -> Duration {
        guard attempt > 0 else { return baseDelay }
        let exponential = pow(multiplier, Double(attempt))
        let baseNanos = baseDelay.components.seconds * 1_000_000_000 + baseDelay.components.attoseconds / 1_000_000_000
        let scaled = Double(baseNanos) * exponential
        let jitterNanos = jitter.components.seconds * 1_000_000_000 + jitter.components.attoseconds / 1_000_000_000
        let jitterNanosInt = Int(jitterNanos)
        let jitterOffset = jitterNanosInt == 0 ? 0 : Int.random(in: -jitterNanosInt...jitterNanosInt)
        let total = Int(scaled) + jitterOffset
        return .nanoseconds(max(0, total))
    }

    public func shouldRetry(_ error: Error) -> Bool { retryPredicate(error) }

    public static func defaultShouldRetry(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .networkConnectionLost, .notConnectedToInternet, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    public static let `default` = APIRetryPolicy()
}

/// Decoder configuration shared by API clients.
public struct APIDecodingConfiguration: Sendable {
    public var dateDecodingStrategy: JSONDecoder.DateDecodingStrategy
    public var keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy
    public var dataDecodingStrategy: JSONDecoder.DataDecodingStrategy
    public var nonConformingFloatDecodingStrategy: JSONDecoder.NonConformingFloatDecodingStrategy

    public init(
        dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .iso8601,
        keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys,
        dataDecodingStrategy: JSONDecoder.DataDecodingStrategy = .base64,
        nonConformingFloatDecodingStrategy: JSONDecoder.NonConformingFloatDecodingStrategy = .throw
    ) {
        self.dateDecodingStrategy = dateDecodingStrategy
        self.keyDecodingStrategy = keyDecodingStrategy
        self.dataDecodingStrategy = dataDecodingStrategy
        self.nonConformingFloatDecodingStrategy = nonConformingFloatDecodingStrategy
    }

    public func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dateDecodingStrategy
        decoder.keyDecodingStrategy = keyDecodingStrategy
        decoder.dataDecodingStrategy = dataDecodingStrategy
        decoder.nonConformingFloatDecodingStrategy = nonConformingFloatDecodingStrategy
        return decoder
    }

    public static let `default` = APIDecodingConfiguration()
}

/// Cache policy used by generated API clients.
public struct APICachePolicy: Sendable {
    public let enabled: Bool
    public let ttl: Duration?

    public init(enabled: Bool = false, ttl: Duration? = nil) {
        self.enabled = enabled
        self.ttl = ttl
    }

    public static let disabled = APICachePolicy()
}

/// Annotation used by @APIClient to override cache policy per endpoint.
public struct Cache: Sendable {
    public let enabled: Bool
    public let ttl: Duration?

    public init(enabled: Bool = true, ttl: Duration? = nil) {
        self.enabled = enabled
        self.ttl = ttl
    }
}
