import Archery
import XCTest

final class KeychainHelperTests: XCTestCase {
    func testMockKeychainRoundTrip() throws {
        let mock = MockKeychainStore()
        let helper = KeychainHelper(store: mock)

        try helper.set("token-123", for: "authToken")
        let token: String? = try helper.value(for: "authToken")
        XCTAssertEqual(token, "token-123")

        try helper.remove("authToken")
        let missing: String? = try helper.value(for: "authToken")
        XCTAssertNil(missing)
    }
}
