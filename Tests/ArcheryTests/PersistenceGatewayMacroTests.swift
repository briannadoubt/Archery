import Archery
import ArcheryMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(ArcheryMacros)
private let testMacros: [String: Macro.Type] = [
    "PersistenceGateway": PersistenceGatewayMacro.self
]
#endif

@MainActor
final class PersistenceGatewayMacroTests: XCTestCase {
    func testExpansionProducesGateway() throws {
        #if canImport(ArcheryMacros)
        assertMacroExpansion(
            """
            @PersistenceGateway
            enum PersistedValues {
                case username(String)
                case score(Int)
            }
            """,
            expandedSource: snapshot("ArcheryMacros/PersistenceGateway/gateway_basic"),
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
        #endif
    }
}
