import Foundation

// MARK: - Record/Replay Test Harness

public protocol Recordable: Codable {
    var timestamp: Date { get }
    var identifier: String { get }
}

public struct NetworkRequest: Recordable {
    public let timestamp: Date
    public let identifier: String
    public let method: String
    public let url: URL
    public let headers: [String: String]
    public let body: Data?
    
    public init(
        method: String,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.timestamp = Date()
        self.identifier = UUID().uuidString
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct NetworkResponse: Recordable {
    public let timestamp: Date
    public let identifier: String
    public let requestId: String
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data?
    public let error: String?
    
    public init(
        requestId: String,
        statusCode: Int,
        headers: [String: String] = [:],
        body: Data? = nil,
        error: String? = nil
    ) {
        self.timestamp = Date()
        self.identifier = UUID().uuidString
        self.requestId = requestId
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.error = error
    }
}

// MARK: - Recording Session

public final class RecordingSession {
    public let id: String
    public let startTime: Date
    public private(set) var endTime: Date?
    public private(set) var requests: [NetworkRequest] = []
    public private(set) var responses: [NetworkResponse] = []
    public private(set) var events: [RecordedEvent] = []
    
    public struct RecordedEvent: Codable {
        public let timestamp: Date
        public let type: String
        public let data: [String: String]
    }
    
    public init(id: String = UUID().uuidString) {
        self.id = id
        self.startTime = Date()
    }
    
    public func record(request: NetworkRequest) {
        requests.append(request)
    }
    
    public func record(response: NetworkResponse) {
        responses.append(response)
    }
    
    public func record(event type: String, data: [String: String] = [:]) {
        let event = RecordedEvent(timestamp: Date(), type: type, data: data)
        events.append(event)
    }
    
    public func end() {
        endTime = Date()
    }
    
    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url)
    }
    
    public static func load(from url: URL) throws -> RecordingSession {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RecordingSession.self, from: data)
    }
}

extension RecordingSession: Codable {}

// MARK: - Replay Engine

public final class ReplayEngine {
    private let session: RecordingSession
    private var currentRequestIndex = 0
    private var currentResponseIndex = 0
    private var currentEventIndex = 0
    
    public init(session: RecordingSession) {
        self.session = session
    }
    
    public func nextRequest() -> NetworkRequest? {
        guard currentRequestIndex < session.requests.count else { return nil }
        let request = session.requests[currentRequestIndex]
        currentRequestIndex += 1
        return request
    }
    
    public func response(for requestId: String) -> NetworkResponse? {
        return session.responses.first { $0.requestId == requestId }
    }
    
    public func nextEvent() -> RecordingSession.RecordedEvent? {
        guard currentEventIndex < session.events.count else { return nil }
        let event = session.events[currentEventIndex]
        currentEventIndex += 1
        return event
    }
    
    public func reset() {
        currentRequestIndex = 0
        currentResponseIndex = 0
        currentEventIndex = 0
    }
    
    public func validate(against liveSession: RecordingSession) -> ValidationResult {
        var differences: [String] = []
        
        // Compare request counts
        if session.requests.count != liveSession.requests.count {
            differences.append("Request count mismatch: recorded=\(session.requests.count), live=\(liveSession.requests.count)")
        }
        
        // Compare requests
        for (index, (recorded, live)) in zip(session.requests, liveSession.requests).enumerated() {
            if recorded.method != live.method || recorded.url != live.url {
                differences.append("Request \(index): method or URL mismatch")
            }
        }
        
        // Compare response status codes
        for (recorded, live) in zip(session.responses, liveSession.responses) {
            if recorded.statusCode != live.statusCode {
                differences.append("Response status mismatch: recorded=\(recorded.statusCode), live=\(live.statusCode)")
            }
        }
        
        return ValidationResult(
            passed: differences.isEmpty,
            differences: differences
        )
    }
    
    public struct ValidationResult {
        public let passed: Bool
        public let differences: [String]
        
        public var summary: String {
            if passed {
                return "✅ Replay validation passed"
            } else {
                return """
                ❌ Replay validation failed
                Differences:
                \(differences.map { "  - \($0)" }.joined(separator: "\n"))
                """
            }
        }
    }
}

// MARK: - Mock Network Layer

public final class MockNetworkLayer {
    private var replayEngine: ReplayEngine?
    private var recordingSession: RecordingSession?
    public var mode: Mode = .passthrough
    
    public enum Mode {
        case passthrough
        case recording
        case replaying
    }
    
    public init() {}
    
    public func startRecording() {
        mode = .recording
        recordingSession = RecordingSession()
    }
    
    public func stopRecording() -> RecordingSession? {
        recordingSession?.end()
        let session = recordingSession
        recordingSession = nil
        mode = .passthrough
        return session
    }
    
    public func startReplaying(session: RecordingSession) {
        mode = .replaying
        replayEngine = ReplayEngine(session: session)
    }
    
    public func stopReplaying() {
        replayEngine = nil
        mode = .passthrough
    }
    
    public func performRequest(_ request: NetworkRequest) async throws -> NetworkResponse {
        switch mode {
        case .passthrough:
            // Perform actual network request
            return try await actualNetworkRequest(request)
            
        case .recording:
            recordingSession?.record(request: request)
            let response = try await actualNetworkRequest(request)
            recordingSession?.record(response: response)
            return response
            
        case .replaying:
            guard let response = replayEngine?.response(for: request.identifier) else {
                throw ReplayError.noRecordedResponse
            }
            return response
        }
    }
    
    private func actualNetworkRequest(_ request: NetworkRequest) async throws -> NetworkResponse {
        // Simplified - would actually perform the request
        return NetworkResponse(
            requestId: request.identifier,
            statusCode: 200,
            body: Data()
        )
    }
}

public enum ReplayError: LocalizedError {
    case noRecordedResponse
    case sessionMismatch
    
    public var errorDescription: String? {
        switch self {
        case .noRecordedResponse:
            return "No recorded response found for request"
        case .sessionMismatch:
            return "Replay session doesn't match current execution"
        }
    }
}

// MARK: - Test Fixtures

public struct TestFixture<T: Codable>: Codable {
    public let name: String
    public let data: T
    public let metadata: [String: String]
    
    public init(name: String, data: T, metadata: [String: String] = [:]) {
        self.name = name
        self.data = data
        self.metadata = metadata
    }
    
    public func save(to directory: URL) throws {
        let url = directory.appendingPathComponent("\(name).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
    
    public static func load(name: String, from directory: URL) throws -> TestFixture<T> {
        let url = directory.appendingPathComponent("\(name).json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(TestFixture<T>.self, from: data)
    }
}