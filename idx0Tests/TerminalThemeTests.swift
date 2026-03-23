import AppKit
import SwiftUI
import XCTest
@testable import idx0

final class TerminalThemeTests: XCTestCase {
    func testGhosttyConfigIncludesCoreColorsAndPalette() {
        let theme = TerminalTheme.theme(withID: "catppuccin-mocha")
        XCTAssertNotNil(theme)
        let config = theme?.ghosttyConfig() ?? ""

        XCTAssertTrue(config.contains("foreground = #cdd6f4"))
        XCTAssertTrue(config.contains("background = #1e1e2e"))
        XCTAssertTrue(config.contains("palette = 0=#45475a"))
        XCTAssertTrue(config.contains("palette = 15=#a6adc8"))
    }

    func testThemeLookupAndColorResolution() {
        XCTAssertNotNil(TerminalTheme.theme(withID: "catppuccin-mocha"))
        XCTAssertNil(TerminalTheme.theme(withID: "missing-theme"))

        let defaultColors = TerminalTheme.resolveColors(themeID: nil)
        XCTAssertFalse(defaultColors.isLight)

        let lightColors = TerminalTheme.resolveColors(themeID: "catppuccin-latte")
        XCTAssertTrue(lightColors.isLight)
    }

    func testThemeCatalogLoadsAndValidates() throws {
        let loadedThemes = try TerminalThemeCatalog.loadThemes()
        XCTAssertEqual(loadedThemes.count, 13)
        XCTAssertEqual(Set(loadedThemes.map(\.id)).count, loadedThemes.count)
        XCTAssertTrue(loadedThemes.allSatisfy { $0.palette.count == 16 })
    }

    func testHexInitializersCreateColors() {
        _ = Color(hex: "#336699")

        let nsColor = NSColor(hex: "#ff0000").usingColorSpace(.deviceRGB)
        XCTAssertNotNil(nsColor)
        XCTAssertEqual(nsColor?.redComponent ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(nsColor?.greenComponent ?? 1, 0, accuracy: 0.001)
        XCTAssertEqual(nsColor?.blueComponent ?? 1, 0, accuracy: 0.001)
    }
}
