import Archery
import SwiftUI
import XCTest

final class DesignTokensRuntimeTests: XCTestCase {
    func testThemesLoadFromManifest() {
        let light = ArcheryDesignTokens.theme(for: .light)
        XCTAssertEqual(light.colorHex(ArcheryDesignTokens.ColorToken.primary), "#0B6EFF")
        XCTAssertEqual(light.colorHex(ArcheryDesignTokens.ColorToken.surfaceRaised), "#F4F6FB")
        XCTAssertEqual(light.spacing(ArcheryDesignTokens.SpacingToken.md), CGFloat(12))
        XCTAssertEqual(light.typography(ArcheryDesignTokens.TypographyToken.title).size, 24)
        XCTAssertEqual(light.typography(ArcheryDesignTokens.TypographyToken.caption).weight, .regular)
    }

    func testVariantOverridesApply() {
        let dark = ArcheryDesignTokens.theme(for: .dark)
        XCTAssertEqual(dark.colorHex(ArcheryDesignTokens.ColorToken.primary), "#5EA1FF")

        let high = ArcheryDesignTokens.theme(for: .highContrast)
        XCTAssertEqual(high.colorHex(ArcheryDesignTokens.ColorToken.surface), "#000000")
        XCTAssertEqual(high.colorHex(ArcheryDesignTokens.ColorToken.accent), "#FF6B00")
    }
}
