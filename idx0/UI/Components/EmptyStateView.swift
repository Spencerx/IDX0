import SwiftUI

struct EmptyStateView: View {
    @Environment(\.themeColors) private var tc

    let icon: String
    let title: String
    let subtitle: String
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .thin))
                .foregroundStyle(tc.mutedText)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tc.secondaryText)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(tc.tertiaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 260)

            if let action, let actionLabel {
                Button(actionLabel, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
}
