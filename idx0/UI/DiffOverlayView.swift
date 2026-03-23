import SwiftUI

struct DiffOverlayView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var sessionService: SessionService
    @Environment(\.themeColors) private var tc

    let sessionID: UUID

    @State private var isLoading = true
    @State private var diffText: String = ""
    @State private var diffStat: DiffStat?
    @State private var changedFiles: [ChangedFileSummary] = []
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    coordinator.showingDiffOverlay = false
                }

            // Diff panel
            VStack(spacing: 0) {
                // Header
                header
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(tc.surface0)

                Rectangle()
                    .fill(tc.divider)
                    .frame(height: 1)

                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                } else if let errorMessage {
                    Spacer()
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(tc.secondaryText)
                    Spacer()
                } else if changedFiles.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 28, weight: .thin))
                            .foregroundStyle(.green.opacity(0.5))
                        Text("No changes")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(tc.secondaryText)
                    }
                    Spacer()
                } else {
                    // File list
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            fileList
                            if !diffText.isEmpty {
                                diffContent
                            }
                        }
                    }
                }

                // Footer
                HStack {
                    Spacer()
                    Text("Esc to close")
                        .font(.system(size: 10))
                        .foregroundStyle(tc.mutedText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(tc.windowBackground)
            }
            .frame(maxWidth: 720, maxHeight: 520)
            .background(tc.sidebarBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(tc.surface2.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        }
        .onAppear { loadDiff() }
        .onExitCommand { coordinator.showingDiffOverlay = false }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Changes")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tc.primaryText)

            if let stat = diffStat {
                HStack(spacing: 6) {
                    if stat.additions > 0 {
                        Text("+\(stat.additions)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.8))
                    }
                    if stat.deletions > 0 {
                        Text("-\(stat.deletions)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                }
            }

            Spacer()

            if let checkpoint = coordinator.autoCheckpointService.latestCheckpoint(for: sessionID) {
                Button("Restore") {
                    restoreCheckpoint(checkpoint)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                coordinator.showingDiffOverlay = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tc.secondaryText)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - File List

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(changedFiles, id: \.path) { file in
                HStack(spacing: 8) {
                    Text(statusIcon(file.status))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor(file.status))
                        .frame(width: 16)

                    Text(file.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(tc.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    if let add = file.additions, add > 0 {
                        Text("+\(add)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.6))
                    }
                    if let del = file.deletions, del > 0 {
                        Text("-\(del)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.red.opacity(0.6))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Diff Content

    private var diffContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(tc.divider)
                .frame(height: 1)
                .padding(.vertical, 4)

            Text(diffText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(tc.primaryText)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }

    // MARK: - Actions

    private func loadDiff() {
        Task {
            guard let session = sessionService.sessions.first(where: { $0.id == sessionID }) else {
                errorMessage = "Session not found"
                isLoading = false
                return
            }

            let path = session.worktreePath ?? session.repoPath
            guard let path else {
                errorMessage = "No repository path"
                isLoading = false
                return
            }

            let git = GitService()

            do {
                // Check if we have a checkpoint to diff against
                if let checkpoint = coordinator.autoCheckpointService.latestCheckpoint(for: sessionID) {
                    changedFiles = try await git.diffNameStatus(
                        path: path,
                        between: checkpoint.commitSHA,
                        and: "HEAD"
                    )
                    // Also include uncommitted changes
                    let uncommitted = try await git.diffNameStatus(path: path)
                    let existingPaths = Set(changedFiles.map(\.path))
                    changedFiles += uncommitted.filter { !existingPaths.contains($0.path) }

                    diffStat = try await git.diffStat(path: path, between: checkpoint.commitSHA, and: "HEAD")
                    diffText = try await git.fullDiff(path: path, since: checkpoint.commitSHA)
                } else {
                    changedFiles = try await git.diffNameStatus(path: path)
                    diffStat = try await git.diffStat(path: path)
                    diffText = try await git.fullDiff(path: path)
                }

                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func restoreCheckpoint(_ checkpoint: AutoCheckpointService.Checkpoint) {
        Task {
            do {
                try await coordinator.autoCheckpointService.restoreCheckpoint(checkpoint)
                coordinator.showingDiffOverlay = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    private func statusIcon(_ status: String) -> String {
        switch status.uppercased().first {
        case "M": return "M"
        case "A": return "A"
        case "D": return "D"
        case "R": return "R"
        default: return "?"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.uppercased().first {
        case "M": return .yellow
        case "A": return .green
        case "D": return .red
        case "R": return .blue
        default: return .gray
        }
    }
}
