import SwiftUI

// MARK: - Advanced

struct InlineAdvancedSettings: View {
    @ObservedObject var sessionService: SessionService
    @Environment(\.themeColors) private var tc

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingSectionHeader(title: "Shell")

            SettingRowView(label: "Preferred Shell Path", caption: "Leave empty to use the system default shell. Changes apply to new sessions.") {
                TextField(
                    "/bin/zsh",
                    text: Binding(
                        get: { sessionService.settings.preferredShellPath ?? "" },
                        set: { newValue in
                            sessionService.saveSettings { settings in
                                let cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                settings.preferredShellPath = cleaned.isEmpty ? nil : cleaned
                            }
                        }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(tc.surface0, in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(tc.surface2.opacity(0.5), lineWidth: 0.5)
                )
                .frame(maxWidth: 280)
            }

            SettingDivider()
            SettingSectionHeader(title: "Reset")

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    sessionService.saveSettings { settings in
                        settings.hasSeenNiriOnboarding = false
                    }
                } label: {
                    Text("Show Niri Onboarding Again")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tc.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(tc.surface0, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(tc.surface2.opacity(0.5), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    sessionService.saveSettings { settings in
                        let preserveFirstRun = settings.hasSeenFirstRun
                        let preserveNiriOnboarding = settings.hasSeenNiriOnboarding
                        settings = AppSettings()
                        settings.hasSeenFirstRun = preserveFirstRun
                        settings.hasSeenNiriOnboarding = preserveNiriOnboarding
                    }
                } label: {
                    Text("Reset All Settings")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(.red.opacity(0.3), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)

                Text("This will reset all settings to their defaults. This cannot be undone.")
                    .font(.system(size: 11))
                    .foregroundStyle(tc.tertiaryText)
            }
            .padding(.vertical, 4)
        }
    }
}
