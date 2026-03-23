import SwiftUI

struct QuickSwitchOverlay: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var sessionService: SessionService
    @EnvironmentObject private var workflowService: WorkflowService
    @Environment(\.themeColors) private var tc

    @FocusState private var queryFocused: Bool
    @State private var query = ""
    @State private var selectedIndex = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tc.tertiaryText)

                    TextField("Switch to session...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($queryFocused)
                        .onSubmit { switchToSelected() }
                        .onChange(of: query) { _, _ in selectedIndex = 0 }
                }
                .padding(12)
                .background(tc.surface0)

                Rectangle()
                    .fill(tc.divider)
                    .frame(height: 1)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(filteredSessions.prefix(10).enumerated()), id: \.element.id) { index, session in
                            sessionRow(session, isSelected: index == selectedIndex)
                                .onTapGesture {
                                    selectedIndex = index
                                    switchToSelected()
                                }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 340)

                if filteredSessions.isEmpty {
                    Text("No matching sessions")
                        .font(.system(size: 12))
                        .foregroundStyle(tc.tertiaryText)
                        .padding(16)
                }
            }
            .frame(width: 420)
            .background(tc.sidebarBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(tc.surface2.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
            .padding(.top, 60)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear { queryFocused = true }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
    }

    @ViewBuilder
    private func sessionRow(_ session: Session, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            // Status dot
            Circle()
                .fill(statusColor(for: session))
                .frame(width: 6, height: 6)

            Image(systemName: session.isWorktreeBacked ? "arrow.triangle.branch" : "terminal")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tc.tertiaryText)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(FuzzyMatch.highlight(query: query, in: session.title))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(session.id == sessionService.selectedSessionID ? tc.secondaryText : tc.primaryText)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let branch = session.branchName, !branch.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 7))
                            Text(branch)
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .foregroundStyle(tc.tertiaryText)
                    }

                    Text(session.subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(tc.mutedText)
                }
            }

            Spacer(minLength: 0)

            Text(relativeTime(session.lastActiveAt))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(tc.mutedText)

            if session.id == sessionService.selectedSessionID {
                Text("current")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(tc.mutedText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(tc.surface0, in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? tc.surface0 : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    private func statusColor(for session: Session) -> Color {
        if let reason = session.latestAttentionReason {
            switch reason {
            case .error: return .red
            case .needsInput: return .orange
            case .completed: return .green
            case .notification: return .yellow
            }
        }
        if session.agentActivity?.isActive == true { return .green }
        if session.agentActivity?.isWaiting == true { return .orange }
        return tc.mutedText
    }

    private var filteredSessions: [Session] {
        let sorted = sessionService.sessions.sorted { $0.lastActiveAt > $1.lastActiveAt }
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return sorted }
        return sorted
            .filter { session in
                let searchText = "\(session.title) \(session.branchName ?? "") \(session.subtitle)".lowercased()
                return FuzzyMatch.matches(query: normalized, text: searchText)
            }
            .sorted { lhs, rhs in
                let lhsText = "\(lhs.title) \(lhs.branchName ?? "") \(lhs.subtitle)".lowercased()
                let rhsText = "\(rhs.title) \(rhs.branchName ?? "") \(rhs.subtitle)".lowercased()
                return FuzzyMatch.score(query: normalized, text: lhsText) > FuzzyMatch.score(query: normalized, text: rhsText)
            }
    }

    private func moveSelection(_ delta: Int) {
        let max = min(filteredSessions.count, 10) - 1
        guard max >= 0 else { return }
        selectedIndex = min(max, Swift.max(0, selectedIndex + delta))
    }

    private func switchToSelected() {
        let sessions = Array(filteredSessions.prefix(10))
        guard selectedIndex < sessions.count else { return }
        let session = sessions[selectedIndex]
        dismiss()
        sessionService.focusSession(session.id)
    }

    private func dismiss() {
        coordinator.showingQuickSwitch = false
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}
