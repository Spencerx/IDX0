import AppKit
import SwiftUI

// MARK: - Alerts Modifier

struct MainWindowAlerts: ViewModifier {
    @EnvironmentObject private var sessionService: SessionService

    func body(content: Content) -> some View {
        content
            .alert(
                "Worktree Session Closed",
                isPresented: Binding(
                    get: { sessionService.pendingWorktreeCleanupNotice != nil },
                    set: { showing in
                        if !showing {
                            sessionService.dismissWorktreeCleanupNotice()
                        }
                    }
                ),
                presenting: sessionService.pendingWorktreeCleanupNotice
            ) { notice in
                Button("Open In Session") {
                    sessionService.createQuickSession(
                        atPath: notice.worktreePath,
                        title: "\(notice.sessionTitle) (Worktree)"
                    )
                    sessionService.dismissWorktreeCleanupNotice()
                }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(notice.worktreePath, forType: .string)
                    sessionService.dismissWorktreeCleanupNotice()
                }
                Button("OK", role: .cancel) {
                    sessionService.dismissWorktreeCleanupNotice()
                }
            } message: { notice in
                Text(worktreeCleanupMessage(for: notice))
            }
            .alert(
                "Delete Clean Worktree",
                isPresented: Binding(
                    get: { sessionService.pendingWorktreeDeletePrompt != nil },
                    set: { showing in
                        if !showing {
                            sessionService.dismissWorktreeDeletePrompt()
                        }
                    }
                ),
                presenting: sessionService.pendingWorktreeDeletePrompt
            ) { prompt in
                Button("Delete", role: .destructive) {
                    Task {
                        await sessionService.confirmDeleteWorktreePrompt()
                    }
                }
                Button("Cancel", role: .cancel) {
                    sessionService.dismissWorktreeDeletePrompt()
                }
            } message: { prompt in
                Text("""
                Delete this clean worktree?
                \(prompt.worktreePath)

                Branch: \(prompt.branchName ?? "unknown")
                Repo: \(prompt.repoPath)
                """)
            }
    }

    private func worktreeCleanupMessage(for notice: WorktreeCleanupNotice) -> String {
        let baseRepo = notice.repoPath ?? notice.worktreePath
        let cleanupCommand = "git -C \"\(baseRepo)\" worktree remove \"\(notice.worktreePath)\""
        return """
        "\(notice.sessionTitle)" was closed and its worktree was kept on disk.
        \(notice.worktreePath)

        Remove it later when safe:
        \(cleanupCommand)
        """
    }
}

