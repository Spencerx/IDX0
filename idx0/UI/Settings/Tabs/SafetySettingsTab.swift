import SwiftUI

// MARK: - Safety Tab

struct SafetySettingsTab: View {
    @ObservedObject var sessionService: SessionService

    var body: some View {
        Form {
            Section("Default Policies") {
                Picker("Default Sandbox Profile", selection: enumBinding(\.defaultSandboxProfile)) {
                    ForEach(SandboxProfile.allCases, id: \.self) { profile in
                        Text(profile.displayLabel).tag(profile)
                    }
                }
                Text("Controls filesystem write access for new sessions")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Picker("Default Network Policy", selection: enumBinding(\.defaultNetworkPolicy)) {
                    ForEach(NetworkPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayLabel).tag(policy)
                    }
                }
                Text("Controls network access for new sessions")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("About Safety") {
                VStack(alignment: .leading, spacing: 8) {
                    profileExplanation("Full Access", "No filesystem or network restrictions. Standard terminal behavior.")
                    profileExplanation("Worktree Write", "Write access limited to the session's repo/worktree directory.")
                    profileExplanation("Worktree + Temp", "Write access to repo/worktree plus system temp directories.")
                }

                Text("Safety note: restrictions reduce accidental damage but do not provide absolute containment. Sandbox enforcement depends on macOS sandbox-exec availability.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
        .padding(10)
    }

    @ViewBuilder
    private func profileExplanation(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func enumBinding<Value: Hashable>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { sessionService.settings[keyPath: keyPath] },
            set: { value in sessionService.saveSettings { $0[keyPath: keyPath] = value } }
        )
    }
}

