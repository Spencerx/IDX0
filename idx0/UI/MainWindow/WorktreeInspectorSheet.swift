import AppKit
import SwiftUI

// MARK: - Worktree Inspector Sheet

struct WorktreeInspectorSheet: View {
    @EnvironmentObject private var sessionService: SessionService

    let repoPath: String

    @State private var isLoading = false
    @State private var errorText: String?
    @State private var items: [WorktreeInspectionItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Worktree Inspector")
                        .font(.headline)
                    Text(repoPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Refresh") { reload() }
                    .disabled(isLoading)
                Button("Done") { sessionService.dismissWorktreeInspector() }
                    .keyboardShortcut(.cancelAction)
            }

            if let errorText, !errorText.isEmpty {
                Text(errorText).font(.caption).foregroundStyle(.red)
            }

            if isLoading {
                EmptyStateView(icon: "arrow.clockwise", title: "Loading", subtitle: "Inspecting worktrees\u{2026}")
            } else if items.isEmpty {
                EmptyStateView(icon: "tray", title: "No worktrees", subtitle: "No worktrees detected for this repo.")
            } else {
                List(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.branchName)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(item.state.rawValue)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(worktreeStateColor(item.state).opacity(0.15), in: Capsule())
                                .foregroundStyle(worktreeStateColor(item.state))
                        }
                        Text(item.worktreePath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 8) {
                            Button("Open In Session") {
                                sessionService.createQuickSession(atPath: item.worktreePath, title: "\(item.branchName) (Worktree)")
                            }
                            .buttonStyle(.bordered).controlSize(.mini)
                            Button("Reveal") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.worktreePath)])
                            }
                            .buttonStyle(.bordered).controlSize(.mini)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .padding(16)
        .onAppear { reload() }
    }

    private func reload() {
        isLoading = true
        errorText = nil
        Task {
            do {
                let inspected = try await sessionService.inspectWorktrees(repoPath: repoPath)
                await MainActor.run { items = inspected; isLoading = false }
            } catch {
                await MainActor.run { isLoading = false; items = []; errorText = error.localizedDescription }
            }
        }
    }

    private func worktreeStateColor(_ state: WorktreeState) -> Color {
        switch state {
        case .clean: return .green
        case .dirty: return .orange
        case .missingOnDisk: return .red
        case .attached: return .blue
        case .pendingDeletion: return .yellow
        }
    }
}

