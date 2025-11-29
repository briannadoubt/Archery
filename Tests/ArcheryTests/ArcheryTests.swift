import XCTest
import Archery

final class ArcheryTests: XCTestCase {
    func testInit() {
        XCTAssertNotNil(Archery())
    }

    func testAlertStateEquatable() {
        let a = AlertState(title: "Oops", message: "Bad")
        let b = AlertState(title: "Oops", message: "Bad")
        let c = AlertState(title: "Other", message: nil)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
