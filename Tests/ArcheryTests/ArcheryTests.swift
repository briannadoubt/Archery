import XCTest
import Archery

final class ArcheryTests: XCTestCase {
    func testModuleLoads() {
        // Basic test to ensure the module loads successfully
        XCTAssertTrue(true)
    }

    func testAlertStateEquatable() {
        let a = AlertState(title: "Oops", message: "Bad")
        let b = AlertState(title: "Oops", message: "Bad")
        let c = AlertState(title: "Other", message: nil)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
