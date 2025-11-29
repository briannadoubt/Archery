import Archery
import XCTest

final class AppErrorTests: XCTestCase {
    func testAlertSurfaceAndRedaction() {
        let error = AppError(
            title: "Network Issue",
            message: "Please try again.",
            category: .network,
            metadata: ["token": "abc123"],
            underlying: URLError(.timedOut)
        )

        let alert = error.alertState
        XCTAssertEqual(alert.title, "Network Issue")
        XCTAssertEqual(alert.message, "Please try again.")

        let log = error.logPayload()
        XCTAssertEqual(log.metadata["token"], "[REDACTED]")
        XCTAssertEqual(log.underlying, "[REDACTED]")

        let analytics = error.analyticsPayload()
        XCTAssertEqual(analytics.category, .network)
    }

    func testWrapHelperUsesFallbackMessage() {
        enum Sample: Error { case failure }
        let wrapped = AppError.wrap(Sample.failure, fallbackMessage: "Fallback", category: .validation)
        XCTAssertEqual(wrapped.message, "Fallback")
        XCTAssertEqual(wrapped.category, .validation)
    }
}
