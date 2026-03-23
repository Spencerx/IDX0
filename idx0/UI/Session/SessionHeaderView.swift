import SwiftUI

struct SessionHeaderView: View {
    @EnvironmentObject private var sessionService: SessionService

    let session: Session

    var body: some View {
        HStack(spacing: 10) {
            // Project icon
            Image(systemName: session.isWorktreeBacked ? "arrow.triangle.branch" : "folder.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))

            // Title
            Text(session.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)

            // Branch pill
            if let branch = session.branchName, !branch.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 8, weight: .semibold))
                    Text(branch)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.white.opacity(0.06), in: Capsule())
            }

            HStack(spacing: 4) {
                Text(session.sandboxProfile.displayLabel)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.mint.opacity(0.85))
                Text("•")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.18))
                Text(session.networkPolicy.displayLabel)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.blue.opacity(0.75))
                Text("• \(session.sandboxEnforcementState.displayLabel)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(enforcementColor.opacity(0.85))
                if session.browserState?.isVisible == true {
                    Text("• Browser")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.indigo.opacity(0.85))
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.white.opacity(0.05), in: Capsule())

            Spacer(minLength: 0)
        }
        .padding(.leading, 78)
        .padding(.trailing, 14)
        .frame(height: 36)
        .background(Color.white.opacity(0.03))
    }

    private var enforcementColor: Color {
        switch session.sandboxEnforcementState {
        case .enforced:
            return .green
        case .degraded:
            return .orange
        case .unenforced:
            return .gray
        }
    }
}
