import ArcheryMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(ArcheryMacros)
private let testMacros: [String: Macro.Type] = ["Repository": RepositoryMacro.self]
#endif

final class RepositoryMacroTests: XCTestCase {
    func testGeneratesProtocolAndMock() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @Repository
            class UserRepository {
                func profile(id: Int) async throws -> String { "ok" }
            }
            """,
            expandedSource: """
            class UserRepository {
                func profile(id: Int) async throws -> String { "ok" }
            }

            protocol UserRepositoryProtocol {
                func profile(id: Int) async throws -> String
            }

            final class MockUserRepository: UserRepositoryProtocol {
                var profileHandler: (Int) async throws -> String?

                init() {
                }

                func profile(id: Int) async throws -> String {
                    if let handler = profileHandler {
                        return try await handler(id)
                    }
                    fatalError("Not implemented in mock")
                }
            }
            """,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }
}
