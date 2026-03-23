import XCTest
@testable import idx0

final class AppSettingsKeyboardTests: XCTestCase {
    func testDecodingMissingKeyboardFieldsUsesDefaults() throws {
        let json = """
        {
          "schemaVersion" : 4,
          "sidebarVisible" : true
        }
        """

        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.keybindingMode, .both)
        XCTAssertEqual(decoded.modKeySetting, .commandOption)
        XCTAssertTrue(decoded.customKeybindings.isEmpty)
        XCTAssertFalse(decoded.hasSeenNiriOnboarding)
        XCTAssertFalse(decoded.cleanupOnClose)
    }

    func testRoundTripPersistsKeyboardSettings() throws {
        var settings = AppSettings()
        settings.keybindingMode = .custom
        settings.modKeySetting = .optionControl
        settings.hasSeenNiriOnboarding = true
        settings.cleanupOnClose = true
        settings.customKeybindings[ShortcutActionID.niriToggleOverview.rawValue] = KeyChord(
            key: .o,
            modifiers: [.option, .control]
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.keybindingMode, .custom)
        XCTAssertEqual(decoded.modKeySetting, .optionControl)
        XCTAssertTrue(decoded.hasSeenNiriOnboarding)
        XCTAssertTrue(decoded.cleanupOnClose)
        XCTAssertEqual(
            decoded.customKeybindings[ShortcutActionID.niriToggleOverview.rawValue],
            KeyChord(key: .o, modifiers: [.option, .control])
        )
    }
}
