import SwiftUI

// MARK: - Safety

struct InlineSafetySettings: View {
    @ObservedObject var sessionService: SessionService
    @Environment(\.themeColors) private var tc

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingSectionHeader(title: "Policies")

            SettingRowView(label: "Sandbox Profile", caption: "Controls filesystem write access for new sessions.") {
                ThemedPicker(
                    options: SandboxProfile.allCases.map { ($0.displayLabel, $0) },
                    selection: enumBinding(\.defaultSandboxProfile)
                )
            }

            SettingRowView(label: "Network Policy", caption: "Controls outbound network access for new sessions.") {
                ThemedPicker(
                    options: NetworkPolicy.allCases.map { ($0.displayLabel, $0) },
                    selection: enumBinding(\.defaultNetworkPolicy)
                )
            }

            SettingDivider()
            SettingSectionHeader(title: "Profile Reference")

            VStack(alignment: .leading, spacing: 10) {
                profileRow("Full Access", "No restrictions. Standard terminal behavior.")
                profileRow("Worktree Write", "Writes limited to repo/worktree directory.")
                profileRow("Worktree + Temp", "Writes to repo/worktree and system temp.")
            }
            .padding(.vertical, 4)

            Text("Restrictions reduce accidental damage but do not provide absolute containment.")
                .font(.system(size: 11))
                .foregroundStyle(tc.tertiaryText)
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func profileRow(_ title: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(tc.secondaryText)
                .frame(width: 120, alignment: .leading)
            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(tc.tertiaryText)
        }
    }

    private func enumBinding<Value: Hashable>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { sessionService.settings[keyPath: keyPath] },
            set: { value in sessionService.saveSettings { $0[keyPath: keyPath] = value } }
        )
    }
}
