import SwiftUI

// MARK: - First Run Sheet

struct FirstRunSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var tc
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var sessionService: SessionService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 3) {
                Text("WELCOME")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(tc.accent)

                Text("Welcome to IDX0")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tc.primaryText)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Rectangle()
                .fill(tc.divider)
                .frame(height: 1)

            // Content
            VStack(alignment: .leading, spacing: 16) {
                Text("IDX0 is terminal-first, with session-first workflow improvements layered on top.")
                    .font(.system(size: 12))
                    .foregroundStyle(tc.secondaryText)
                    .lineSpacing(2)

                VStack(alignment: .leading, spacing: 8) {
                    bullet("Use IDX0 as a normal daily terminal.")
                    bullet("Sessions are first-class for parallel coding work.")
                    bullet("Repo and worktree session creation is built in.")
                    bullet("Advanced supervision features are additive, not required.")
                }

                Rectangle()
                    .fill(tc.divider)
                    .frame(height: 1)

                // Quick Start shortcuts
                VStack(alignment: .leading, spacing: 8) {
                    Text("QUICK START")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(tc.accent)

                    shortcutHint(for: .newQuickSession, label: "New instant session")
                    shortcutHint(for: .commandPalette, label: "Command palette")
                    shortcutHint(for: .toggleSidebar, label: "Toggle sidebar")
                    shortcutHint(for: .quickSwitchSession, label: "Quick switch sessions")
                }

                // Footer buttons
                HStack {
                    Spacer()
                    Button("Continue") {
                        markSeen()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)

                    Button("Create Session") {
                        markSeen()
                        coordinator.triggerPrimaryNewSessionAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .background(tc.sidebarBackground)
        .frame(width: 520)
    }

    private func markSeen() {
        sessionService.saveSettings { settings in
            settings.hasSeenFirstRun = true
        }
        dismiss()
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(tc.accent)
                .frame(width: 4, height: 4)
                .padding(.top, 5)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(tc.primaryText)
        }
    }

    private func shortcutHint(for action: ShortcutActionID, label: String) -> some View {
        let shortcut = ShortcutRegistry.shared.displayLabel(for: action, settings: sessionService.settings) ?? "-"
        return HStack(spacing: 10) {
            Text(shortcut)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(tc.tertiaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tc.surface0, in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(tc.surface2.opacity(0.5), lineWidth: 0.5)
                )
                .frame(minWidth: 50, alignment: .center)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(tc.secondaryText)
        }
    }
}
