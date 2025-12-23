import Foundation
import Combine

// MARK: - Record/Replay Harness

/// Records and replays network requests for deterministic testing
public actor RecordReplayHarness {

    public enum Mode: Sendable {
        case record
        case replay
        case passthrough
    }

    private let mode: Mode
    private let storage: RecordingStorage
    private var recordings: [String: Recording] = [:]
    private let session: URLSession

    public init(
        mode: Mode,
        storage: RecordingStorage = FileRecordingStorage(),
        session: URLSession = .shared
    ) {
        self.mode = mode
        self.storage = storage
        self.session = session
    }
    
    // MARK: - Setup
    
    /// Load existing recordings
    public func loadRecordings() async throws {
        recordings = try await storage.load()
    }
    
    /// Save current recordings
    public func saveRecordings() async throws {
        try await storage.save(recordings)
    }
    
    // MARK: - Request Handling
    
    /// Execute request with record/replay
    public func execute(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let key = requestKey(for: request)
        
        switch mode {
        case .record:
            return try await recordRequest(request, key: key)
            
        case .replay:
            return try await replayRequest(request, key: key)
            
        case .passthrough:
            return try await session.data(for: request)
        }
    }
    
    private func recordRequest(_ request: URLRequest, key: String) async throws -> (Data, URLResponse) {
        // Execute real request
        let (data, response) = try await session.data(for: request)
        
        // Record the interaction
        let recording = Recording(
            request: sanitizeRequest(request),
            response: sanitizeResponse(response),
            data: data,
            timestamp: Date()
        )
        
        recordings[key] = recording
        
        return (data, response)
    }
    
    private func replayRequest(_ request: URLRequest, key: String) async throws -> (Data, URLResponse) {
        guard let recording = recordings[key] else {
            throw RecordReplayError.noRecording(key: key)
        }
        
        // Validate request matches recording
        if !matchesRecording(request, recording: recording) {
            throw RecordReplayError.requestMismatch(key: key)
        }
        
        // Simulate network delay
        if let delay = recording.simulatedDelay {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        return (recording.data, recording.response)
    }
    
    // MARK: - Key Generation
    
    private func requestKey(for request: URLRequest) -> String {
        var components: [String] = []
        
        // Method
        components.append(request.httpMethod ?? "GET")
        
        // URL without query parameters
        if let url = request.url?.absoluteString.split(separator: "?").first {
            components.append(String(url))
        }
        
        // Sorted query parameters
        if let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems {
            let sorted = queryItems
                .sorted { $0.name < $1.name }
                .map { "\($0.name)=\($0.value ?? "")" }
                .joined(separator: "&")
            components.append(sorted)
        }
        
        // Body hash (if present)
        if let body = request.httpBody {
            components.append(body.sha256Hash())
        }
        
        return components.joined(separator: "|")
    }
    
    // MARK: - Sanitization
    
    private func sanitizeRequest(_ request: URLRequest) -> URLRequest {
        var sanitized = request
        
        // Remove sensitive headers
        sanitized.allHTTPHeaderFields?.removeValue(forKey: "Authorization")
        sanitized.allHTTPHeaderFields?.removeValue(forKey: "X-API-Key")
        
        return sanitized
    }
    
    private func sanitizeResponse(_ response: URLResponse) -> URLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            return response
        }
        
        var sanitizedHeaders = httpResponse.allHeaderFields as? [String: String] ?? [:]
        sanitizedHeaders.removeValue(forKey: "Set-Cookie")
        
        return HTTPURLResponse(
            url: httpResponse.url!,
            statusCode: httpResponse.statusCode,
            httpVersion: nil,
            headerFields: sanitizedHeaders
        )!
    }
    
    // MARK: - Matching
    
    private func matchesRecording(_ request: URLRequest, recording: Recording) -> Bool {
        // Check method
        if request.httpMethod != recording.request.httpMethod {
            return false
        }
        
        // Check URL path
        if request.url?.path != recording.request.url?.path {
            return false
        }
        
        // Check query parameters (order-independent)
        let requestQuery = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let recordedQuery = URLComponents(url: recording.request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        
        if Set(requestQuery) != Set(recordedQuery) {
            return false
        }
        
        return true
    }
}

// MARK: - Recording Model

public struct Recording: Codable, Sendable {
    public let request: URLRequest
    public let response: URLResponse
    public let data: Data
    public let timestamp: Date
    public var simulatedDelay: TimeInterval?
    
    enum CodingKeys: String, CodingKey {
        case request, response, data, timestamp, simulatedDelay
    }
    
    public init(
        request: URLRequest,
        response: URLResponse,
        data: Data,
        timestamp: Date,
        simulatedDelay: TimeInterval? = nil
    ) {
        self.request = request
        self.response = response
        self.data = data
        self.timestamp = timestamp
        self.simulatedDelay = simulatedDelay
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode URLRequest manually
        let requestData = try container.decode(Data.self, forKey: .request)
        request = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSURLRequest.self, from: requestData)! as URLRequest

        data = try container.decode(Data.self, forKey: .data)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        simulatedDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .simulatedDelay)

        // Decode URLResponse
        let responseData = try container.decode(Data.self, forKey: .response)
        response = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: URLResponse.self,
            from: responseData
        )!
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Encode URLRequest manually
        let requestData = try NSKeyedArchiver.archivedData(
            withRootObject: request,
            requiringSecureCoding: true
        )
        try container.encode(requestData, forKey: .request)

        try container.encode(data, forKey: .data)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(simulatedDelay, forKey: .simulatedDelay)

        // Encode URLResponse
        let responseData = try NSKeyedArchiver.archivedData(
            withRootObject: response,
            requiringSecureCoding: true
        )
        try container.encode(responseData, forKey: .response)
    }
}

// MARK: - Storage

public protocol RecordingStorage: Sendable {
    func load() async throws -> [String: Recording]
    func save(_ recordings: [String: Recording]) async throws
}

/// File-based recording storage
public final class FileRecordingStorage: RecordingStorage, Sendable {
    private let directoryURL: URL

    public init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NetworkRecordings")
    }

    public func load() async throws -> [String: Recording] {
        let fileURL = directoryURL.appendingPathComponent("recordings.json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([String: Recording].self, from: data)
    }

    public func save(_ recordings: [String: Recording]) async throws {
        // Create directory if needed
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let fileURL = directoryURL.appendingPathComponent("recordings.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(recordings)
        try data.write(to: fileURL)
    }
}

/// In-memory recording storage
public actor MemoryRecordingStorage: RecordingStorage {
    private var recordings: [String: Recording] = [:]

    public init() {}

    public func load() async throws -> [String: Recording] {
        recordings
    }

    public func save(_ recordings: [String: Recording]) async throws {
        self.recordings = recordings
    }
}

// MARK: - Deterministic Previews

/// Provides deterministic data for SwiftUI previews
public struct DeterministicPreviewData {
    
    /// Fixed date for previews
    public static let previewDate = Date(timeIntervalSince1970: 1704067200) // 2024-01-01
    
    /// Fixed UUID for previews
    public static let previewUUID = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!
    
    /// Fixed random seed
    public static let previewSeed: UInt64 = 12345
    
    /// Create deterministic user
    public static func previewUser(id: Int = 1) -> PreviewUser {
        PreviewUser(
            id: "user-\(id)",
            name: "Preview User \(id)",
            email: "user\(id)@preview.test",
            avatarURL: URL(string: "https://api.dicebear.com/7.x/avataaars/svg?seed=\(id)")
        )
    }
    
    /// Create deterministic list
    public static func previewList<T>(
        count: Int,
        generator: (Int) -> T
    ) -> [T] {
        (0..<count).map(generator)
    }
    
    /// Create deterministic text
    public static func previewText(wordCount: Int) -> String {
        let words = ["Lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit", "sed", "do"]
        var random = SeededRandom(seed: previewSeed)
        
        return (0..<wordCount).map { _ in
            words.randomElement(using: &random)!
        }.joined(separator: " ")
    }
}

public struct PreviewUser {
    public let id: String
    public let name: String
    public let email: String
    public let avatarURL: URL?
}

// MARK: - Errors

public enum RecordReplayError: LocalizedError {
    case noRecording(key: String)
    case requestMismatch(key: String)
    case storageError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .noRecording(let key):
            return "No recording found for key: \(key)"
        case .requestMismatch(let key):
            return "Request doesn't match recording: \(key)"
        case .storageError(let error):
            return "Storage error: \(error.localizedDescription)"
        }
    }
}

// MARK: - URLSession Extension

public extension URLSession {
    
    /// Create session with record/replay harness
    static func recordReplay(
        mode: RecordReplayHarness.Mode,
        storage: RecordingStorage = FileRecordingStorage()
    ) -> URLSession {
        let harness = RecordReplayHarness(mode: mode, storage: storage)
        
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [RecordReplayURLProtocol.self]
        
        // Store harness in protocol
        RecordReplayURLProtocol.harness = harness
        
        return URLSession(configuration: configuration)
    }
}

/// URLProtocol for intercepting requests
/// Note: Uses @preconcurrency to bridge with pre-Swift-concurrency URLProtocol APIs
@preconcurrency
class RecordReplayURLProtocol: URLProtocol {
    nonisolated(unsafe) static var harness: RecordReplayHarness?

    override class func canInit(with request: URLRequest) -> Bool {
        harness != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let currentRequest = request
        let currentClient = client
        // Use nonisolated(unsafe) because URLProtocol callbacks must run on main queue
        // and we're explicitly dispatching there. This bridges pre-concurrency URLProtocol APIs.
        nonisolated(unsafe) let protocolSelf = self

        Task { @Sendable in
            do {
                guard let harness = Self.harness else {
                    throw RecordReplayError.storageError(NSError(domain: "No harness", code: -1))
                }

                let (data, response) = try await harness.execute(currentRequest)

                // URLProtocolClient methods - dispatch back to main queue
                DispatchQueue.main.async {
                    currentClient?.urlProtocol(protocolSelf, didReceive: response, cacheStoragePolicy: .notAllowed)
                    currentClient?.urlProtocol(protocolSelf, didLoad: data)
                    currentClient?.urlProtocolDidFinishLoading(protocolSelf)
                }
            } catch {
                DispatchQueue.main.async {
                    currentClient?.urlProtocol(protocolSelf, didFailWithError: error)
                }
            }
        }
    }

    override func stopLoading() {
        // No-op
    }
}

// MARK: - Helpers

extension Data {
    func sha256Hash() -> String {
        // Simplified hash for demo
        let hash = self.reduce(0) { $0 &+ Int($1) }
        return String(hash)
    }
}