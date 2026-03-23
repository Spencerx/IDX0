import SwiftUI

// MARK: - First Run Sheet

struct FirstRunSheet: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var sessionService: SessionService

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Welcome to IDX0")
                .font(.title2.weight(.semibold))

            Text("IDX0 is terminal-first, with session-first workflow improvements layered on top.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                bullet("Use IDX0 as a normal daily terminal.")
                bullet("Sessions are first-class for parallel coding work.")
                bullet("Repo and worktree session creation is built in.")
                bullet("Advanced supervision features are additive, not required.")
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Quick Start")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                shortcutHint(for: .newQuickSession, label: "New instant session")
                shortcutHint(for: .commandPalette, label: "Command palette")
                shortcutHint(for: .toggleSidebar, label: "Toggle sidebar")
                shortcutHint(for: .quickSwitchSession, label: "Quick switch sessions")
            }

            HStack {
                Spacer()

                Button("Continue") {
                    markSeen()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create Session") {
                    markSeen()
                    coordinator.triggerPrimaryNewSessionAction()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func markSeen() {
        sessionService.saveSettings { settings in
            settings.hasSeenFirstRun = true
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
        }
    }

    private func shortcutHint(_ shortcut: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Text(shortcut)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
                .frame(width: 50, alignment: .center)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func shortcutHint(for action: ShortcutActionID, label: String) -> some View {
        let shortcut = ShortcutRegistry.shared.displayLabel(for: action, settings: sessionService.settings) ?? "-"
        return shortcutHint(shortcut, label)
    }
}
