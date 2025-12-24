import Archery
import Foundation
import XCTest

#if os(macOS)
import ArcheryMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport

private let testMacros: [String: Macro.Type] = ["APIClient": APIClientMacro.self]
#endif

@APIClient
class CountingAPI {
    nonisolated(unsafe) static var calls = 0

    func fetch(id: Int) async throws -> Int {
        CountingAPI.calls += 1
        return id
    }
}

@APIClient
class FlakyAPI {
    nonisolated(unsafe) var attempts = 0

    func load() async throws -> String {
        attempts += 1
        if attempts < 3 { throw URLError(.cannotConnectToHost) }
        return "ok"
    }
}

@APIClient
class FatalAPI {
    nonisolated(unsafe) static var calls = 0
    func go() async throws -> Int { Self.calls += 1; throw Fatal.nope }
}

enum Fatal: Error { case nope }

@APIClient
class OverrideAPI {
    nonisolated(unsafe) var hits = 0

    @Cache(enabled: true, ttl: .milliseconds(1))
    func load(id: Int) async throws -> Int {
        hits += 1
        return id
    }
}

@MainActor
final class APIClientMacroTests: XCTestCase {
    #if os(macOS)
    func testMacroExpansionIncludesLiveMockAndDI() throws {
        assertMacroExpansion(
            """
            @APIClient
            class WeatherAPI {
                func forecast(city: String) async throws -> Data { Data() }
            }
            """,
            expandedSource: snapshot("ArcheryMacros/APIClient/apiclient_basic"),
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testDiagnosticsRequireAsync() throws {
        assertMacroExpansion(
            """
            @APIClient
            class SyncAPI {
                func ping() -> Bool { true }
            }
            """,
            expandedSource: snapshot("ArcheryMacros/APIClient/apiclient_sync_warning"),
            diagnostics: [
                DiagnosticSpec(message: "@APIClient methods must be async: ping", line: 3, column: 5, severity: .warning)
            ],
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }
    #endif

    func testRetryHonorsPolicy() async throws {
        let api = FlakyAPI()
        let policy = APIRetryPolicy(maxRetries: 2, baseDelay: .milliseconds(1), multiplier: 1, jitter: .zero)
        let client = FlakyAPILive(baseFactory: { api }, retryPolicy: policy)

        let value = try await client.load()
        XCTAssertEqual(value, "ok")
        XCTAssertEqual(api.attempts, 3)
    }

    func testCachingUsesCachedValue() async throws {
        CountingAPI.calls = 0
        let client = CountingAPILive(cachePolicy: .init(enabled: true))

        let first = try await client.fetch(id: 42)
        let second = try await client.fetch(id: 42)

        XCTAssertEqual(first, 42)
        XCTAssertEqual(second, 42)
        XCTAssertEqual(CountingAPI.calls, 1)
    }

    func testCacheTTLExpiresEntry() async throws {
        CountingAPI.calls = 0
        let client = CountingAPILive(cachePolicy: .init(enabled: true, ttl: .milliseconds(1)))

        _ = try await client.fetch(id: 1)
        try await Task.sleep(for: .milliseconds(5))
        _ = try await client.fetch(id: 1)

        XCTAssertEqual(CountingAPI.calls, 2)
    }

    func testRetrySkipsNonRetriableError() async {
        FatalAPI.calls = 0
        let policy = APIRetryPolicy(maxRetries: 3, shouldRetry: { _ in false })
        let client = FatalAPILive(retryPolicy: policy)

        do {
            _ = try await client.go()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(FatalAPI.calls, 1)
        }
    }

    func testCacheAttributeOverridesPolicy() async throws {
        let api = OverrideAPI()
        let client = OverrideAPILive(baseFactory: { api }, cachePolicy: .disabled)

        _ = try await client.load(id: 1)
        try await Task.sleep(for: .milliseconds(5))
        _ = try await client.load(id: 1)

        // TTL forced expiry; hits incremented twice even though global cache disabled.
        XCTAssertEqual(api.hits, 2)
    }

    func testDecodingConfigurationFixture() throws {
        struct PlayerPayload: Decodable, Equatable {
            let playerName: String
            let joinedAt: Date
        }

        let json = """
        {"player_name":"Robin","joined_at":"2024-06-01T12:00:00Z"}
        """.data(using: .utf8)!

        let decoder = APIDecodingConfiguration(
            dateDecodingStrategy: .iso8601,
            keyDecodingStrategy: .convertFromSnakeCase
        ).makeDecoder()

        let payload = try decoder.decode(PlayerPayload.self, from: json)
        XCTAssertEqual(payload.playerName, "Robin")
    }
}
