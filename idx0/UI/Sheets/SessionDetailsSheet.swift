import SwiftUI

struct SessionDetailsSheet: View {
    @EnvironmentObject private var sessionService: SessionService
    @EnvironmentObject private var workflowService: WorkflowService

    let sessionID: UUID

    var body: some View {
        Group {
            if let session = sessionService.sessions.first(where: { $0.id == sessionID }) {
                detailsBody(session: session)
            } else {
                Text("Session unavailable.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
        }
        .frame(width: 380)
    }

    @ViewBuilder
    private func detailsBody(session: Session) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.title)
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                if let repoPath = session.repoPath {
                    detailRow("Repo", value: repoPath)
                }
                if let branchName = session.branchName {
                    detailRow("Branch", value: branchName)
                }
                if let worktreePath = session.worktreePath {
                    detailRow("Worktree", value: worktreePath)
                }
                if let worktreeState = session.worktreeState {
                    detailRow("Worktree State", value: worktreeState.rawValue)
                }
                detailRow("Sandbox Profile", value: session.sandboxProfile.displayLabel)
                detailRow("Network", value: session.networkPolicy.displayLabel)
                detailRow("Enforcement", value: session.sandboxEnforcementState.displayLabel)
                detailRow("Writable Roots", value: sessionService.sandboxWritableRoots(for: session.id).joined(separator: " | "))
                detailRow("Launch CWD", value: session.lastLaunchCwd)
                if let browser = session.browserState, browser.isVisible {
                    detailRow("Browser URL", value: browser.currentURL ?? "(empty)")
                }
                if let statusText = session.statusText, !statusText.isEmpty {
                    detailRow("Status", value: statusText)
                }
                detailRow("Queue Items", value: "\(workflowService.queueItems(for: session.id).count)")
                detailRow("Checkpoints", value: "\(workflowService.checkpoints(for: session.id).count)")
                detailRow("Timeline Events", value: "\(workflowService.timeline(for: session.id).count)")

                let usage = workflowService.sessionUsage(for: session.id)
                if usage.eventCount > 0 {
                    Divider()
                    Text("Usage")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    detailRow("Events", value: "\(usage.eventCount)")
                    if usage.totalInputTokens > 0 || usage.totalOutputTokens > 0 {
                        detailRow("Input Tokens", value: "\(usage.totalInputTokens)")
                        detailRow("Output Tokens", value: "\(usage.totalOutputTokens)")
                    }
                    if usage.totalEstimatedCostUSD > 0 {
                        detailRow("Est. Cost", value: String(format: "$%.4f", usage.totalEstimatedCostUSD))
                    }
                }

                detailRow("Created", value: session.createdAt.formatted())
                detailRow("Last Active", value: session.lastActiveAt.formatted())
            }

            Divider()
            HStack(spacing: 8) {
                Button("Create Checkpoint") {
                    Task {
                        _ = try? await workflowService.createManualCheckpoint(
                            sessionID: session.id,
                            title: "Manual Checkpoint",
                            summary: "Created from session details",
                            requestReview: false
                        )
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button(workflowService.isSessionParked(session.id) ? "Unpark" : "Park") {
                    if workflowService.isSessionParked(session.id) {
                        workflowService.unparkSession(session.id)
                    } else {
                        workflowService.parkSession(session.id)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            if session.isWorktreeBacked {
                Divider()
                HStack(spacing: 8) {
                    Button("Refresh State") {
                        Task {
                            await sessionService.inspectWorktreeState(for: session.id)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Button("Open Worktree In Session") {
                        sessionService.openWorktreeInNewSession(for: session.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            if let repoPath = session.repoPath {
                HStack(spacing: 8) {
                    Button("Inspect Repo Worktrees") {
                        sessionService.presentWorktreeInspector(repoPath: repoPath)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .padding(14)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}
