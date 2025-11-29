import Archery
import ArcheryMacros
import Foundation
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(ArcheryMacros)
private let testMacros: [String: Macro.Type] = ["Repository": RepositoryMacro.self]
#endif

@Repository
class CountingRepository {
    nonisolated(unsafe) static var calls = 0

    func fetch(id: Int) async throws -> Int {
        CountingRepository.calls += 1
        try await Task.sleep(nanoseconds: 50_000_000)
        return id
    }
}

@Repository
class FailingRepository {
    enum SampleError: Error { case boom }
    func explode() async throws -> String {
        throw SampleError.boom
    }
}

@MainActor
final class RepositoryMacroTests: XCTestCase {
    func testMacroExpansionIncludesLiveMockAndDI() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @Repository
            class UserRepository {
                func profile(id: Int) async throws -> String { "ok" }
            }
            """,
            expandedSource: snapshot("ArcheryMacros/Repository/repo_basic"),
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }

    func testDiagnosticsRequireAsync() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @Repository
            class SyncRepository {
                func profile(id: Int) -> String { "ok" }
            }
            """,
            expandedSource: snapshot("ArcheryMacros/Repository/repo_sync_warning"),
            diagnostics: [
                DiagnosticSpec(message: "@Repository methods must be async: profile", line: 3, column: 5, severity: .warning)
            ],
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }

    func testCachingAndCoalescing() async throws {
        CountingRepository.calls = 0
        let repo = CountingRepositoryLive(enableCaching: true, enableCoalescing: true)

        async let first = repo.fetch(id: 1)
        async let second = repo.fetch(id: 1)

        let results = try await [first, second]
        XCTAssertEqual(results, [1, 1])
        XCTAssertEqual(CountingRepository.calls, 1)
    }

    func testErrorNormalizationAddsContext() async {
        let repo = FailingRepositoryLive()

        do {
            _ = try await repo.explode()
            XCTFail("Expected an error")
        } catch let error as RepositoryError {
            switch error {
            case .unknown(let underlying):
                if let context = underlying as? RepositorySourceError {
                    XCTAssertTrue(context.function.contains("explode"))
                    XCTAssertTrue(context.file.contains("RepositoryMacroTests"))
                } else {
                    XCTFail("Missing contextual error wrapper")
                }
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testTracingHookEmitsEvent() async throws {
        actor TraceSink {
            private var events: [RepositoryTraceEvent] = []
            func record(_ event: RepositoryTraceEvent) { events.append(event) }
            func snapshot() -> [RepositoryTraceEvent] { events }
        }

        let sink = TraceSink()
        let repo = CountingRepositoryLive(enableTracing: true, traceHandler: { event in
            Task { await sink.record(event) }
        })

        _ = try await repo.fetch(id: 7)

        let events = await sink.snapshot()
        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.function, "fetch(id: Int)")
        XCTAssertEqual(event.key, "fetch|7")
        XCTAssertFalse(event.cacheHit)
        XCTAssertFalse(event.coalesced)
        XCTAssertNil(event.error)
    }
}
