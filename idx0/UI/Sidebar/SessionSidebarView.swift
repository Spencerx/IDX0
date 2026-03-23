import SwiftUI

struct SessionSidebarView: View {
    @EnvironmentObject private var sessionService: SessionService
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var workflowService: WorkflowService
    @Environment(\.themeColors) private var tc

    @State private var draggedGroupID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Spacer()

                Button {
                    coordinator.triggerOpenFolderSession()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tc.secondaryText)
                        .frame(width: 22, height: 22)
                        .background(tc.surface0.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Open Folder as New Session")

                Button {
                    coordinator.triggerSidebarNewTerminalAction()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tc.secondaryText)
                        .frame(width: 22, height: 22)
                        .background(tc.surface0.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("New Terminal in Current Directory")
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)

            HStack {
                Text("SESSIONS")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(tc.mutedText)

                // Attention badge
                let needsAttention = coordinator.terminalMonitor.sessionsNeedingAttention()
                if needsAttention > 0 {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 5, height: 5)
                        Text("\(needsAttention)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                }

                Spacer()

                Text("\(sessionService.sessions.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tc.mutedText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sessionService.projectSections.enumerated()), id: \.element.id) { sectionIndex, section in
                        // Project folder row
                        TreeFolderRow(group: section.group, sessionCount: section.sessions.count)
                            .onDrag {
                                NSItemProvider(object: section.group.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: ProjectGroupDropDelegate(
                                sessionService: sessionService,
                                targetIndex: sectionIndex,
                                draggedGroupID: $draggedGroupID
                            ))
                            .contextMenu {
                                let groups = sessionService.projectGroups
                                let index = groups.firstIndex(where: { $0.id == section.group.id })

                                if let index, index > 0 {
                                    Button("Move Up") {
                                        sessionService.moveProjectGroups(from: IndexSet(integer: index), to: index - 1)
                                    }
                                }
                                if let index, index < groups.count - 1 {
                                    Button("Move Down") {
                                        sessionService.moveProjectGroups(from: IndexSet(integer: index), to: index + 2)
                                    }
                                }
                            }

                        // Session children (indented)
                        if !section.group.isCollapsed {
                            ForEach(Array(section.sessions.enumerated()), id: \.element.id) { sessionIndex, session in
                                let isLast = sessionIndex == section.sessions.count - 1
                                let siblingTitles = section.sessions.map(\.title)

                                SessionRowContainer(
                                    session: session,
                                    isLast: isLast,
                                    disambiguationIndex: disambiguationIndex(
                                        for: session, in: siblingTitles
                                    )
                                ) {
                                    sessionContextMenu(session: session)
                                }

                                // Show pane children when session has splits
                                if let paneTree = sessionService.paneTrees[session.id] {
                                    let paneIDs = paneTree.terminalControllerIDs
                                    if paneIDs.count > 1 {
                                        ForEach(Array(paneIDs.enumerated()), id: \.element) { paneIndex, controllerID in
                                            PaneSubRow(
                                                sessionID: session.id,
                                                controllerID: controllerID,
                                                paneIndex: paneIndex + 1,
                                                isLast: paneIndex == paneIDs.count - 1,
                                                isSessionLast: isLast
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            // Settings button at bottom
            Divider()
                .background(tc.divider)

            Button {
                coordinator.showingSettings.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gear")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(coordinator.showingSettings ? tc.accent : tc.secondaryText)
                    Text("Settings")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(coordinator.showingSettings ? tc.primaryText : tc.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(coordinator.showingSettings ? tc.surface1.opacity(0.6) : Color.clear)
            }
            .buttonStyle(.plain)
        }
        .background(tc.sidebarBackground)
    }

    // MARK: - Disambiguation

    /// If multiple sessions in the same group have the same display title,
    /// return a 1-based index to append. Returns nil if the title is unique.
    private func disambiguationIndex(for session: Session, in titles: [String]) -> Int? {
        let myTitle = Self.stripHostPrefix(session.title)
        let duplicates = titles.filter { Self.stripHostPrefix($0) == myTitle }
        guard duplicates.count > 1 else { return nil }
        // Find which occurrence this session is (by matching full title for ordering)
        let matchingFullTitles = titles.enumerated().filter { Self.stripHostPrefix($0.element) == myTitle }
        guard let pos = matchingFullTitles.firstIndex(where: { $0.element == session.title }) else { return nil }
        return pos + 1
    }

    static func stripHostPrefix(_ title: String) -> String {
        if let colonIndex = title.firstIndex(of: ":") {
            let beforeColon = title[title.startIndex..<colonIndex]
            if beforeColon.contains("@") {
                return String(title[title.index(after: colonIndex)...])
            }
        }
        return title
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func sessionContextMenu(session: Session) -> some View {
        Button("Rename...") {
            coordinator.presentRenameSessionSheet(session: session)
        }

        Button(session.isPinned ? "Unpin Session" : "Pin Session") {
            sessionService.togglePinned(session.id)
        }

        Divider()

        if session.isWorktreeBacked || session.repoPath != nil {
            if session.isWorktreeBacked {
                Menu("Worktree") {
                    Button("Reveal in Finder") {
                        sessionService.revealWorktree(for: session.id)
                    }
                    Button("Delete Clean Worktree...") {
                        sessionService.promptDeleteWorktree(for: session.id)
                    }
                }
            }

            if let repoPath = session.repoPath {
                Button("Inspect Repo Worktrees") {
                    sessionService.presentWorktreeInspector(repoPath: repoPath)
                }
            }

            Divider()
        }

        Button("Close Session") {
            sessionService.closeSession(session.id)
        }
    }
}

// MARK: - Session Row Container (hover + selection)

private struct SessionRowContainer<ContextMenu: View>: View {
    @EnvironmentObject private var sessionService: SessionService
    @Environment(\.themeColors) private var tc

    let session: Session
    let isLast: Bool
    let disambiguationIndex: Int?
    @ViewBuilder let contextMenu: () -> ContextMenu

    @State private var isHovering = false

    var body: some View {
        let isSelected = sessionService.selectedSessionID == session.id

        SessionSidebarRowView(
            session: session,
            isLast: isLast,
            disambiguationIndex: disambiguationIndex
        )
        .padding(.leading, 12)
        .background(rowBackground(isSelected: isSelected))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            sessionService.focusSession(session.id)
        }
        .contextMenu {
            contextMenu()
        }
    }

    private func rowBackground(isSelected: Bool) -> some View {
        Group {
            if isSelected {
                tc.surface1
            } else if isHovering {
                tc.surface0.opacity(0.5)
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - Pane Sub Row

private struct PaneSubRow: View {
    @EnvironmentObject private var sessionService: SessionService
    @Environment(\.themeColors) private var tc

    let sessionID: UUID
    let controllerID: UUID
    let paneIndex: Int
    let isLast: Bool
    let isSessionLast: Bool

    @State private var isHovering = false

    var body: some View {
        let isFocused = sessionService.focusedPaneControllerID[sessionID] == controllerID

        HStack(spacing: 0) {
            // Extra indent: session tree guide continuation + pane tree guide
            Canvas { context, size in
                let midX = size.width / 2
                let midY = size.height / 2
                let color = tc.surface2

                // Vertical line (continues from session)
                if !isSessionLast || !isLast {
                    var vPath = Path()
                    vPath.move(to: CGPoint(x: midX - 8, y: 0))
                    vPath.addLine(to: CGPoint(x: midX - 8, y: isSessionLast ? (isLast ? midY : size.height) : size.height))
                    context.stroke(vPath, with: .color(color), lineWidth: 1)
                }

                // Pane branch
                var vPath2 = Path()
                vPath2.move(to: CGPoint(x: midX, y: 0))
                vPath2.addLine(to: CGPoint(x: midX, y: isLast ? midY : size.height))
                context.stroke(vPath2, with: .color(color), lineWidth: 1)

                var hPath = Path()
                hPath.move(to: CGPoint(x: midX, y: midY))
                hPath.addLine(to: CGPoint(x: size.width, y: midY))
                context.stroke(hPath, with: .color(color), lineWidth: 1)
            }
            .frame(width: 24)

            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(isFocused ? tc.accent : tc.tertiaryText)
                .frame(width: 14)

            Text("Pane \(paneIndex)")
                .font(.system(size: 10, weight: isFocused ? .medium : .regular))
                .foregroundStyle(isFocused ? tc.primaryText : tc.secondaryText)
                .lineLimit(1)
                .padding(.leading, 4)

            Spacer(minLength: 4)

            if isFocused {
                Circle()
                    .fill(tc.accent)
                    .frame(width: 5, height: 5)
                    .padding(.trailing, 8)
            }
        }
        .padding(.vertical, 3)
        .padding(.leading, 24)
        .padding(.trailing, 8)
        .background(
            isFocused ? tc.accent.opacity(0.08) :
            isHovering ? tc.surface0.opacity(0.4) :
            Color.clear
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            sessionService.setFocusedPane(sessionID: sessionID, controllerID: controllerID)
            sessionService.focusSession(sessionID)
        }
        .contextMenu {
            Button("Close Pane") {
                // Temporarily set focus to this pane then close it
                sessionService.setFocusedPane(sessionID: sessionID, controllerID: controllerID)
                sessionService.closePane(sessionID: sessionID)
            }
        }
    }
}

// MARK: - Tree Folder Row

private struct TreeFolderRow: View {
    @EnvironmentObject private var sessionService: SessionService
    @Environment(\.themeColors) private var tc

    let group: ProjectGroup
    let sessionCount: Int

    @State private var isHovering = false

    var body: some View {
        Button {
            sessionService.toggleProjectCollapsed(group.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: group.isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(tc.tertiaryText)
                    .frame(width: 10)

                Image(systemName: group.isCollapsed ? "folder" : "folder.fill")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(tc.accent)

                Text(group.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tc.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(sessionCount)")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(tc.tertiaryText)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
        .background(isHovering ? tc.surface0.opacity(0.4) : Color.clear)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Project Group Drop Delegate

private struct ProjectGroupDropDelegate: DropDelegate {
    let sessionService: SessionService
    let targetIndex: Int
    @Binding var draggedGroupID: UUID?

    func performDrop(info: DropInfo) -> Bool {
        draggedGroupID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedGroupID else {
            if let item = info.itemProviders(for: [.text]).first {
                item.loadObject(ofClass: NSString.self) { reading, _ in
                    guard let str = reading as? String, let id = UUID(uuidString: str) else { return }
                    DispatchQueue.main.async {
                        draggedGroupID = id
                    }
                }
            }
            return
        }

        let groups = sessionService.projectGroups
        guard let fromIndex = groups.firstIndex(where: { $0.id == draggedID }),
              fromIndex != targetIndex else { return }

        let dest = fromIndex < targetIndex ? targetIndex + 1 : targetIndex
        sessionService.moveProjectGroups(from: IndexSet(integer: fromIndex), to: dest)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
