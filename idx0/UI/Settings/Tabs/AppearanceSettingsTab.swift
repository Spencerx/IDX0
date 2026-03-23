import SwiftUI

// MARK: - Appearance Tab

struct AppearanceSettingsTab: View {
    @ObservedObject var sessionService: SessionService

    @State private var needsRestart = false
    @State private var hoveredThemeID: String?

    private var currentThemeID: String {
        sessionService.settings.terminalThemeID ?? "none"
    }

    /// The theme to preview — hovered theme takes priority, then the saved one.
    private var previewThemeID: String? {
        let id = hoveredThemeID ?? sessionService.settings.terminalThemeID
        return id
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
        VStack(spacing: 0) {
            // Theme preview at top
            themePreviewPanel
                .padding(10)

            // Theme grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ThemeCard(
                        label: "System Default",
                        isSelected: currentThemeID == "none",
                        theme: nil
                    )
                    .onTapGesture { selectedThemeID.wrappedValue = "none" }
                    .onHover { hovering in hoveredThemeID = hovering ? nil : nil }

                    ForEach(TerminalTheme.allThemes) { theme in
                        ThemeCard(
                            label: theme.displayName,
                            isSelected: currentThemeID == theme.id,
                            theme: theme
                        )
                        .onTapGesture { selectedThemeID.wrappedValue = theme.id }
                        .onHover { hovering in hoveredThemeID = hovering ? theme.id : nil }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }

            if needsRestart {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("Terminal colors update on new/relaunched sessions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var themePreviewPanel: some View {
        let theme = TerminalTheme.theme(withID: previewThemeID ?? "")
        let colors = AppThemeColors(theme: theme)

        VStack(spacing: 0) {
            // Mock top bar
            HStack(spacing: 6) {
                Circle().fill(.red.opacity(0.8)).frame(width: 8, height: 8)
                Circle().fill(.yellow.opacity(0.8)).frame(width: 8, height: 8)
                Circle().fill(.green.opacity(0.8)).frame(width: 8, height: 8)
                Spacer()
                Text(theme?.displayName ?? "Default")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(colors.primaryText)
                Spacer()
                // Balance spacing
                Color.clear.frame(width: 36, height: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(colors.windowBackground)

            HStack(spacing: 0) {
                // Mock sidebar
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colors.surface1)
                        .frame(height: 22)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colors.surface0.opacity(0.5))
                        .frame(height: 22)
                    Spacer()
                }
                .padding(6)
                .frame(width: 70)
                .background(colors.sidebarBackground)

                // Mock terminal area
                VStack(alignment: .leading, spacing: 3) {
                    if let theme {
                        HStack(spacing: 3) {
                            ForEach(0..<8, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(hex: theme.palette[i]))
                                    .frame(width: 16, height: 10)
                            }
                        }
                        HStack(spacing: 3) {
                            ForEach(8..<16, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(hex: theme.palette[i]))
                                    .frame(width: 16, height: 10)
                            }
                        }
                    }
                    Text("$ echo hello")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(colors.primaryText)
                    Text("hello")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(colors.secondaryText)
                    Spacer()
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.contentBackground)
            }
            .frame(height: 90)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: previewThemeID)
    }
}

struct ThemeCard: View {
    let label: String
    let isSelected: Bool
    let theme: TerminalTheme?

    var body: some View {
        VStack(spacing: 0) {
            // Color bar
            HStack(spacing: 0) {
                if let theme {
                    ForEach(0..<8, id: \.self) { i in
                        Color(hex: theme.palette[i])
                    }
                } else {
                    Color(white: 0.15)
                }
            }
            .frame(height: 24)

            // Label
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(theme.map { Color(hex: $0.base) } ?? Color(white: 0.12))
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.blue.opacity(0.6) : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
        )
    }
}

