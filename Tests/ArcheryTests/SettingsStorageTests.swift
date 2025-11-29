import Archery
import SwiftUI
import XCTest

@MainActor
final class SettingsStorageTests: XCTestCase {
    func testAppStorageEncodesCodable() {
        guard #available(iOS 14, macOS 11, tvOS 14, watchOS 7, visionOS 1, *) else {
            return
        }

        struct Settings {
            @ArcheryAppStorage("archery.appstorage.test", store: UserDefaults(suiteName: "archery-appstorage")!) var username: String = "Guest"
        }

        let defaults = UserDefaults(suiteName: "archery-appstorage")!
        defaults.removePersistentDomain(forName: "archery-appstorage")

        var settings = Settings()
        XCTAssertEqual(settings.username, "Guest")
        settings.username = "Robin"

        let reread = Settings()
        XCTAssertEqual(reread.username, "Robin")
    }
}
