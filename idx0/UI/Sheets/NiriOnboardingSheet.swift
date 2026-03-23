import SwiftUI

struct NiriOnboardingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var sessionService: SessionService

    private let registry = ShortcutRegistry.shared

    private var niriRows: [ShortcutDescriptor] {
        registry.descriptors(in: .niri)
            .filter { $0.remappable }
            .filter { registry.primaryBinding(for: $0.id, settings: sessionService.settings) != nil }
    }

    private let coreGlobalIDs: [ShortcutActionID] = [
        .newQuickSession,
        .commandPalette,
        .quickSwitchSession,
        .toggleSidebar,
        .closeSession,
        .splitRight,
        .splitDown,
        .toggleBrowserSplit,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome To Niri Canvas")
                .font(.title3.weight(.semibold))

            Text("These are the defaults for your active keybinding profile. You can remap everything in Settings > Keyboard.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Niri Controls") {
                        ForEach(niriRows, id: \.id) { descriptor in
                            shortcutRow(
                                title: descriptor.title,
                                shortcut: registry.displayLabel(for: descriptor.id, settings: sessionService.settings) ?? "Unassigned"
                            )
                        }
                    }

                    section("Core Global Shortcuts") {
                        ForEach(coreGlobalIDs, id: \.self) { action in
                            if let descriptor = registry.descriptor(for: action) {
                                shortcutRow(
                                    title: descriptor.title,
                                    shortcut: registry.displayLabel(for: action, settings: sessionService.settings) ?? "Unassigned"
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            HStack {
                Button("View Full Keyboard Shortcuts") {
                    coordinator.showingKeyboardShortcuts = true
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Start Using Niri") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 620, height: 620)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(.secondary)

            content()
        }
    }

    private func shortcutRow(title: String, shortcut: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Text(shortcut)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
        }
    }
}
