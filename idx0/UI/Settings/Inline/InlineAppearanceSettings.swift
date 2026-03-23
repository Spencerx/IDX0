import SwiftUI

// MARK: - Appearance

struct InlineAppearanceSettings: View {
    @ObservedObject var sessionService: SessionService
    @Environment(\.themeColors) private var tc

    @State private var needsRestart = false
    @State private var hoveredThemeID: String?

    private var currentThemeID: String {
        sessionService.settings.terminalThemeID ?? "none"
    }

    private var previewThemeID: String? {
        hoveredThemeID ?? sessionService.settings.terminalThemeID
    }

    private var selectedThemeID: Binding<String> {
        Binding(
            get: { currentThemeID },
            set: { value in
                let id = value == "none" ? nil : value
                sessionService.saveSettings { $0.terminalThemeID = id }
                GhosttyAppHost.writeThemeConfig(themeID: id)
                needsRestart = true
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingSectionHeader(title: "Theme")

            Text("Choose a color theme for the terminal and UI. Hover to preview.")
                .font(.system(size: 11))
                .foregroundStyle(tc.tertiaryText)
                .padding(.bottom, 12)

            themePreviewPanel
                .padding(.bottom, 14)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                themeCard(label: "System Default", themeID: "none", theme: nil)

                ForEach(TerminalTheme.allThemes) { theme in
                    themeCard(label: theme.displayName, themeID: theme.id, theme: theme)
                }
            }

            if needsRestart {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 5, height: 5)
                    Text("Theme colors apply on new sessions")
                        .font(.system(size: 11))
                        .foregroundStyle(tc.tertiaryText)
                }
                .padding(.top, 10)
            }
        }
    }

    @ViewBuilder
    private func themeCard(label: String, themeID: String, theme: TerminalTheme?) -> some View {
        let isSelected = currentThemeID == themeID

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if let theme {
                    ForEach(0..<8, id: \.self) { i in
                        Color(hex: theme.palette[i])
                    }
                } else {
                    tc.surface0
                }
            }
            .frame(height: 20)

            HStack {
                Text(label)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? tc.primaryText : tc.tertiaryText)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(tc.accent)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(theme.map { Color(hex: $0.base) } ?? tc.surface0.opacity(0.5))
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isSelected ? tc.accent.opacity(0.6) : tc.surface2.opacity(0.4), lineWidth: isSelected ? 1.5 : 0.5)
        )
        .onTapGesture { selectedThemeID.wrappedValue = themeID }
        .onHover { hovering in hoveredThemeID = hovering ? (themeID == "none" ? nil : themeID) : nil }
    }

    @ViewBuilder
    private var themePreviewPanel: some View {
        let theme = TerminalTheme.theme(withID: previewThemeID ?? "")
        let colors = AppThemeColors(theme: theme)

        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(.red.opacity(0.7)).frame(width: 7, height: 7)
                Circle().fill(.yellow.opacity(0.7)).frame(width: 7, height: 7)
                Circle().fill(.green.opacity(0.7)).frame(width: 7, height: 7)
                Spacer()
                Text(theme?.displayName ?? "Default")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(colors.secondaryText)
                Spacer()
                Color.clear.frame(width: 30, height: 7)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(colors.windowBackground)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    RoundedRectangle(cornerRadius: 2).fill(colors.surface1).frame(height: 16)
                    RoundedRectangle(cornerRadius: 2).fill(colors.surface0.opacity(0.5)).frame(height: 16)
                    Spacer()
                }
                .padding(5)
                .frame(width: 55)
                .background(colors.sidebarBackground)

                VStack(alignment: .leading, spacing: 2) {
                    if let theme {
                        HStack(spacing: 2) {
                            ForEach(0..<8, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color(hex: theme.palette[i]))
                                    .frame(width: 14, height: 8)
                            }
                        }
                        HStack(spacing: 2) {
                            ForEach(8..<16, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color(hex: theme.palette[i]))
                                    .frame(width: 14, height: 8)
                            }
                        }
                    }
                    Text("$ echo hello")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(colors.primaryText)
                    Text("hello")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(colors.secondaryText)
                    Spacer()
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.contentBackground)
            }
            .frame(height: 70)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(tc.surface2.opacity(0.3), lineWidth: 0.5))
        .animation(.easeOut(duration: 0.15), value: previewThemeID)
    }
}
