import SwiftUI

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var tc
    @EnvironmentObject private var sessionService: SessionService

    private let registry = ShortcutRegistry.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — matches onboarding header style
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Keyboard Shortcuts")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tc.primaryText)
                    Text("Mode: \(sessionService.settings.keybindingMode.displayName)  \u{2022}  Mod: \(sessionService.settings.modKeySetting.displayName)")
                        .font(.system(size: 10))
                        .foregroundStyle(tc.tertiaryText)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Rectangle()
                .fill(tc.divider)
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(ShortcutSection.allCases, id: \.self) { section in
                        let sectionRows = registry.descriptors(in: section)
                            .filter { $0.remappable }
                            .filter { registry.primaryBinding(for: $0.id, settings: sessionService.settings) != nil }

                        if !sectionRows.isEmpty {
                            shortcutSection(section.title) {
                                ForEach(sectionRows, id: \.id) { descriptor in
                                    shortcutRow(
                                        descriptor.title,
                                        registry.displayLabel(for: descriptor.id, settings: sessionService.settings) ?? "Unassigned"
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(tc.sidebarBackground)
        .frame(width: 460, height: 560)
    }

    @ViewBuilder
    private func shortcutSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(tc.accent)
                .padding(.bottom, 2)

            content()
        }
    }

    private func shortcutRow(_ label: String, _ shortcut: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(tc.secondaryText)

            Spacer(minLength: 16)

            Text(shortcut)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(tc.tertiaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tc.surface0, in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(tc.surface2.opacity(0.5), lineWidth: 0.5)
                )
        }
    }
}
