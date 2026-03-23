import Foundation
import SwiftUI

// MARK: - Theme Definition

struct TerminalTheme: Identifiable, Equatable {
    let id: String
    let displayName: String
    let isLight: Bool

    // Terminal colors
    let foreground: String
    let background: String
    let cursorColor: String
    let selectionBackground: String
    let selectionForeground: String?
    /// ANSI palette: 16 colors (0-15), hex strings with #
    let palette: [String]

    // App UI semantic colors (Catppuccin naming)
    let crust: String      // deepest bg (window chrome)
    let mantle: String     // sidebar bg
    let base: String       // main content bg (same as terminal background)
    let surface0: String   // raised surfaces
    let surface1: String   // higher surfaces
    let surface2: String   // highest surfaces / borders
    let overlay0: String   // inactive/muted elements
    let overlay1: String   // secondary text
    let overlay2: String   // tertiary elements
    let text: String       // primary text
    let subtext0: String   // dimmer body text
    let subtext1: String   // slightly dim text
    let accent: String     // accent color (mauve by default)

    func ghosttyConfig() -> String {
        var lines: [String] = []
        lines.append("foreground = \(foreground)")
        lines.append("background = \(background)")
        lines.append("cursor-color = \(cursorColor)")
        lines.append("selection-background = \(selectionBackground)")
        if let selFg = selectionForeground {
            lines.append("selection-foreground = \(selFg)")
        }
        for (i, color) in palette.enumerated() {
            lines.append("palette = \(i)=\(color)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

extension TerminalTheme {
    static let allThemes: [TerminalTheme] = TerminalThemeCatalog.themes

    static func theme(withID id: String) -> TerminalTheme? {
        allThemes.first { $0.id == id }
    }

    /// Resolve current AppThemeColors from a theme ID (nil = default).
    static func resolveColors(themeID: String?) -> AppThemeColors {
        guard let themeID, let theme = theme(withID: themeID) else {
            return .default
        }
        return AppThemeColors(theme: theme)
    }
}

// MARK: - SwiftUI Color Helpers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8) & 0xFF) / 255
        let b = CGFloat(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Resolved Theme Colors (for SwiftUI views)

struct AppThemeColors {
    let windowBackground: Color
    let sidebarBackground: Color
    let contentBackground: Color
    let surface0: Color
    let surface1: Color
    let surface2: Color
    let overlay0: Color
    let overlay1: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let mutedText: Color
    let accent: Color
    let divider: Color
    let isLight: Bool

    // NSColor versions for window configurator
    let nsWindowBackground: NSColor

    static let `default` = AppThemeColors(theme: nil)

    init(theme: TerminalTheme?) {
        if let theme {
            windowBackground = Color(hex: theme.base)
            sidebarBackground = Color(hex: theme.mantle)
            contentBackground = Color(hex: theme.base)
            surface0 = Color(hex: theme.surface0)
            surface1 = Color(hex: theme.surface1)
            surface2 = Color(hex: theme.surface2)
            overlay0 = Color(hex: theme.overlay0)
            overlay1 = Color(hex: theme.overlay1)
            primaryText = Color(hex: theme.text)
            secondaryText = Color(hex: theme.subtext1)
            tertiaryText = Color(hex: theme.subtext0)
            mutedText = Color(hex: theme.overlay0)
            accent = Color(hex: theme.accent)
            divider = Color(hex: theme.surface2).opacity(0.5)
            isLight = theme.isLight
            nsWindowBackground = NSColor(hex: theme.base)
        } else {
            // Default dark theme (matches original hardcoded values)
            windowBackground = Color(red: 0.16, green: 0.17, blue: 0.20)
            sidebarBackground = Color(white: 0.10)
            contentBackground = Color(red: 0.16, green: 0.17, blue: 0.20)
            surface0 = Color(white: 0.14)
            surface1 = Color(white: 0.18)
            surface2 = Color(white: 0.22)
            overlay0 = Color.white.opacity(0.2)
            overlay1 = Color.white.opacity(0.35)
            primaryText = Color.white.opacity(0.85)
            secondaryText = Color.white.opacity(0.55)
            tertiaryText = Color.white.opacity(0.35)
            mutedText = Color.white.opacity(0.2)
            accent = Color.purple
            divider = Color.white.opacity(0.04)
            isLight = false
            nsWindowBackground = NSColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1)
        }
    }
}

// MARK: - Environment Key

private struct ThemeColorsKey: EnvironmentKey {
    static let defaultValue = AppThemeColors.default
}

extension EnvironmentValues {
    var themeColors: AppThemeColors {
        get { self[ThemeColorsKey.self] }
        set { self[ThemeColorsKey.self] = newValue }
    }
}
