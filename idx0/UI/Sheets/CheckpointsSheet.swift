import SwiftUI

struct CheckpointsSidebar: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var sessionService: SessionService
    @EnvironmentObject private var workflowService: WorkflowService

    @State private var newTitle = ""
    @State private var isCreating = false

    private var sessionID: UUID? {
        sessionService.selectedSessionID
    }

    private var checkpoints: [Checkpoint] {
        guard let id = sessionID else { return [] }
        return workflowService.checkpoints(for: id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                Text("Checkpoints")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("\(checkpoints.count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.white.opacity(0.06), in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.top, 36) // clear title bar
            .padding(.bottom, 8)

            Divider().opacity(0.2)

            if checkpoints.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "flag")
                        .font(.system(size: 20, weight: .thin))
                        .foregroundStyle(.white.opacity(0.15))
                    Text("No checkpoints yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(checkpoints) { checkpoint in
                            CheckpointRow(checkpoint: checkpoint) {
                                forkFromCheckpoint(checkpoint)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider().opacity(0.2)

            // Quick create
            HStack(spacing: 6) {
                TextField("Checkpoint name...", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit { createCheckpoint() }

                Button {
                    createCheckpoint()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(canCreate ? .white.opacity(0.5) : .white.opacity(0.15))
                }
                .buttonStyle(.plain)
                .disabled(!canCreate)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: NSColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1)))
    }

    private var canCreate: Bool {
        !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCreating && sessionID != nil
    }

    private func createCheckpoint() {
        guard let id = sessionID else { return }
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        isCreating = true
        let capturedTitle = title
        newTitle = ""
        Task {
            _ = try? await workflowService.createManualCheckpoint(
                sessionID: id,
                title: capturedTitle,
                summary: capturedTitle,
                requestReview: false
            )
            await MainActor.run {
                isCreating = false
            }
        }
    }

    private func forkFromCheckpoint(_ checkpoint: Checkpoint) {
        let worktreePath = checkpoint.worktreePath ?? checkpoint.repoPath
        let forkTitle = "Fork: \(checkpoint.title)"

        if let path = worktreePath {
            sessionService.createQuickSession(atPath: path, title: forkTitle)
        } else {
            sessionService.createQuickSession(atPath: nil, title: forkTitle)
        }
    }
}

// MARK: - Checkpoint Row

private struct CheckpointRow: View {
    let checkpoint: Checkpoint
    let onFork: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                sourceDot
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(checkpoint.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)

                    Text(checkpoint.createdAt, style: .relative)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.25))
                }

                Spacer(minLength: 4)

                if isHovering {
                    Button {
                        onFork()
                    } label: {
                        Image(systemName: "arrow.branch")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Fork session from this checkpoint")
                }
            }

            // Metadata row
            HStack(spacing: 6) {
                if let sha = checkpoint.commitSHA {
                    Text(String(sha.prefix(7)))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }

                if let diff = checkpoint.diffStat, diff.filesChanged > 0 {
                    HStack(spacing: 2) {
                        Text("+\(diff.additions)")
                            .foregroundStyle(.green.opacity(0.5))
                        Text("-\(diff.deletions)")
                            .foregroundStyle(.red.opacity(0.5))
                    }
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                }

                if let branch = checkpoint.branchName {
                    Text(branch)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.leading, 12) // align with text after dot
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovering ? .white.opacity(0.04) : .clear)
        .onHover { isHovering = $0 }
    }

    private var sourceDot: some View {
        let color: Color = {
            switch checkpoint.source {
            case .manual: return .blue
            case .agentEvent: return .green
            case .autoCommit: return .orange
            }
        }()
        return Circle()
            .fill(color.opacity(0.6))
            .frame(width: 5, height: 5)
    }
}
