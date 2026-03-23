import SwiftUI

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionService: SessionService

    private let registry = ShortcutRegistry.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Keyboard Shortcuts")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Mode: \(sessionService.settings.keybindingMode.displayName)  •  Mod: \(sessionService.settings.modKeySetting.displayName)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Rectangle()
                .fill(Color.white.opacity(0.06))
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
                .padding(16)
            }
        }
        .frame(width: 460, height: 560)
    }

    @ViewBuilder
    private func shortcutSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.3))
                .padding(.bottom, 2)

            content()
        }
    }

    private func shortcutRow(_ label: String, _ shortcut: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))

            Spacer(minLength: 16)

            Text(shortcut)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
        }
    }
}
