import Foundation

enum TerminalThemeCatalogError: Error, LocalizedError {
    case resourceNotFound
    case decodeFailed(Error)
    case emptyField(themeID: String, field: String)
    case duplicateThemeID(String)
    case invalidPaletteCount(themeID: String, count: Int)
    case invalidHexColor(themeID: String, field: String, value: String)

    var errorDescription: String? {
        switch self {
        case .resourceNotFound:
            return "Unable to find Themes/terminal-themes.json in app resources."
        case .decodeFailed(let error):
            return "Failed to decode terminal themes JSON: \(error.localizedDescription)"
        case .emptyField(let themeID, let field):
            return "Theme '\(themeID)' has an empty required field: \(field)."
        case .duplicateThemeID(let id):
            return "Duplicate terminal theme ID detected: \(id)."
        case .invalidPaletteCount(let themeID, let count):
            return "Theme '\(themeID)' has palette count \(count); expected 16."
        case .invalidHexColor(let themeID, let field, let value):
            return "Theme '\(themeID)' has invalid hex color for \(field): \(value)."
        }
    }
}

enum TerminalThemeCatalog {
    static let themes: [TerminalTheme] = {
        do {
            return try loadThemes()
        } catch {
            assertionFailure("TerminalThemeCatalog load failed: \(error.localizedDescription)")
            return []
        }
    }()

    static func loadThemes() throws -> [TerminalTheme] {
        guard let resourceURL = themeResourceURL() else {
            throw TerminalThemeCatalogError.resourceNotFound
        }

        let data = try Data(contentsOf: resourceURL)
        let records: [ThemeRecord]
        do {
            records = try JSONDecoder().decode([ThemeRecord].self, from: data)
        } catch {
            throw TerminalThemeCatalogError.decodeFailed(error)
        }

        let parsedThemes = records.map(\.theme)
        try validate(themes: parsedThemes)
        return parsedThemes
    }

    static func validate(themes: [TerminalTheme]) throws {
        var seenIDs = Set<String>()

        for theme in themes {
            let themeID = theme.id

            if themeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw TerminalThemeCatalogError.emptyField(themeID: "<unknown>", field: "id")
            }
            if theme.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw TerminalThemeCatalogError.emptyField(themeID: themeID, field: "displayName")
            }
            if !seenIDs.insert(themeID).inserted {
                throw TerminalThemeCatalogError.duplicateThemeID(themeID)
            }
            if theme.palette.count != 16 {
                throw TerminalThemeCatalogError.invalidPaletteCount(themeID: themeID, count: theme.palette.count)
            }

            for (index, color) in theme.palette.enumerated() {
                try validateHexColor(color, themeID: themeID, field: "palette[\(index)]")
            }

            try validateHexColor(theme.foreground, themeID: themeID, field: "foreground")
            try validateHexColor(theme.background, themeID: themeID, field: "background")
            try validateHexColor(theme.cursorColor, themeID: themeID, field: "cursorColor")
            try validateHexColor(theme.selectionBackground, themeID: themeID, field: "selectionBackground")
            if let selectionForeground = theme.selectionForeground {
                try validateHexColor(selectionForeground, themeID: themeID, field: "selectionForeground")
            }
            try validateHexColor(theme.crust, themeID: themeID, field: "crust")
            try validateHexColor(theme.mantle, themeID: themeID, field: "mantle")
            try validateHexColor(theme.base, themeID: themeID, field: "base")
            try validateHexColor(theme.surface0, themeID: themeID, field: "surface0")
            try validateHexColor(theme.surface1, themeID: themeID, field: "surface1")
            try validateHexColor(theme.surface2, themeID: themeID, field: "surface2")
            try validateHexColor(theme.overlay0, themeID: themeID, field: "overlay0")
            try validateHexColor(theme.overlay1, themeID: themeID, field: "overlay1")
            try validateHexColor(theme.overlay2, themeID: themeID, field: "overlay2")
            try validateHexColor(theme.text, themeID: themeID, field: "text")
            try validateHexColor(theme.subtext0, themeID: themeID, field: "subtext0")
            try validateHexColor(theme.subtext1, themeID: themeID, field: "subtext1")
            try validateHexColor(theme.accent, themeID: themeID, field: "accent")
        }
    }

    private static func validateHexColor(_ value: String, themeID: String, field: String) throws {
        if !HexColorValidator.isValid(value) {
            throw TerminalThemeCatalogError.invalidHexColor(themeID: themeID, field: field, value: value)
        }
    }

    private static func themeResourceURL() -> URL? {
        for bundle in candidateBundles() {
            if let url = bundle.url(forResource: "terminal-themes", withExtension: "json", subdirectory: "Themes") {
                return url
            }
            if let url = bundle.url(forResource: "terminal-themes", withExtension: "json") {
                return url
            }
            if let resourceURL = bundle.resourceURL {
                let nested = resourceURL
                    .appendingPathComponent("Themes", isDirectory: true)
                    .appendingPathComponent("terminal-themes.json")
                if FileManager.default.fileExists(atPath: nested.path) {
                    return nested
                }
            }
        }
        return nil
    }

    private static func candidateBundles() -> [Bundle] {
        var bundles: [Bundle] = [Bundle.main, Bundle(for: BundleToken.self)]
        bundles.append(contentsOf: Bundle.allFrameworks)
        bundles.append(contentsOf: Bundle.allBundles)
        return bundles
    }

    private final class BundleToken {}

    private struct ThemeRecord: Decodable {
        let id: String
        let displayName: String
        let isLight: Bool
        let foreground: String
        let background: String
        let cursorColor: String
        let selectionBackground: String
        let selectionForeground: String?
        let palette: [String]
        let crust: String
        let mantle: String
        let base: String
        let surface0: String
        let surface1: String
        let surface2: String
        let overlay0: String
        let overlay1: String
        let overlay2: String
        let text: String
        let subtext0: String
        let subtext1: String
        let accent: String

        var theme: TerminalTheme {
            TerminalTheme(
                id: id,
                displayName: displayName,
                isLight: isLight,
                foreground: foreground,
                background: background,
                cursorColor: cursorColor,
                selectionBackground: selectionBackground,
                selectionForeground: selectionForeground,
                palette: palette,
                crust: crust,
                mantle: mantle,
                base: base,
                surface0: surface0,
                surface1: surface1,
                surface2: surface2,
                overlay0: overlay0,
                overlay1: overlay1,
                overlay2: overlay2,
                text: text,
                subtext0: subtext0,
                subtext1: subtext1,
                accent: accent
            )
        }
    }
}

private enum HexColorValidator {
    static let regex = try! NSRegularExpression(pattern: "^#[0-9A-Fa-f]{6}$")

    static func isValid(_ value: String) -> Bool {
        let range = NSRange(location: 0, length: value.utf16.count)
        return regex.firstMatch(in: value, options: [], range: range) != nil
    }
}
