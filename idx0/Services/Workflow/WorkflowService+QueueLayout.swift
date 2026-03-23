import Foundation

extension WorkflowService {
    func queueItems(for sessionID: UUID) -> [SupervisionQueueItem] {
        unresolvedQueueItems.filter { $0.sessionID == sessionID }
    }

    func checkpoints(for sessionID: UUID) -> [Checkpoint] {
        checkpoints
            .filter { $0.sessionID == sessionID }
            .sorted { lhs, rhs in
                lhs.createdAt > rhs.createdAt
            }
    }

    func timeline(for sessionID: UUID) -> [TimelineItem] {
        sortedTimelineItems.filter { $0.sessionID == sessionID }
    }

    func sessionUsage(for sessionID: UUID) -> SessionUsage {
        let events = timeline(for: sessionID)
        return SessionUsage(
            totalInputTokens: 0,
            totalOutputTokens: 0,
            totalEstimatedCostUSD: 0,
            eventCount: events.count
        )
    }

    func markQueueItemResolved(_ id: UUID) {
        queueItems = queueService.resolve(itemID: id, in: queueItems)
        persistSoon()
    }

    func highestPriorityCategory(for sessionID: UUID) -> QueueItemCategory? {
        queueService.highestPriorityCategory(for: sessionID, in: queueItems)
    }

    func openRailSurface(_ surface: WorkflowRailSurface) {
        selectedRailSurface = surface
        if let sessionID = sessionService.selectedSessionID {
            layoutState.lastRailSurfaceBySession[sessionID] = surface
        }
        persistSoon()
    }

    func selectCheckpoint(_ checkpointID: UUID?) {
        selectedCheckpointID = checkpointID
    }

    func selectReview(_ reviewID: UUID?) {
        selectedReviewID = reviewID
    }

    func selectHandoff(_ handoffID: UUID?) {
        selectedHandoffID = handoffID
    }

    func openCheckpoint(_ checkpointID: UUID) {
        selectedCheckpointID = checkpointID
        openRailSurface(.checkpoints)
    }

    func openReview(_ reviewID: UUID) {
        selectedReviewID = reviewID
        openRailSurface(.review)
    }

    func openHandoff(_ handoffID: UUID) {
        selectedHandoffID = handoffID
        openRailSurface(.handoffs)
    }

    func setComparePreset(left: CompareInput?, right: CompareInput?) {
        comparePresetLeft = left
        comparePresetRight = right
    }

    func beginCompare(with checkpointID: UUID) {
        comparePresetLeft = .checkpoint(checkpointID)
        comparePresetRight = nil
        openRailSurface(.compare)
    }

    func navigateFromQueueItem(_ item: SupervisionQueueItem) {
        sessionService.focusSession(item.sessionID)

        guard let relatedObjectID = item.relatedObjectID else {
            return
        }

        if reviews.contains(where: { $0.id == relatedObjectID }) {
            openReview(relatedObjectID)
            return
        }

        if checkpoints.contains(where: { $0.id == relatedObjectID }) {
            openCheckpoint(relatedObjectID)
            return
        }

        if handoffs.contains(where: { $0.id == relatedObjectID }) {
            openHandoff(relatedObjectID)
        }
    }

    func parkSession(_ sessionID: UUID) {
        guard !layoutState.parkedSessionIDs.contains(sessionID) else { return }
        layoutState.parkedSessionIDs.append(sessionID)
        persistSoon()
    }

    func unparkSession(_ sessionID: UUID) {
        layoutState.parkedSessionIDs.removeAll { $0 == sessionID }
        persistSoon()
    }

    func isSessionParked(_ sessionID: UUID) -> Bool {
        layoutState.parkedSessionIDs.contains(sessionID)
    }

    func stackSession(_ sessionID: UUID) {
        if layoutState.stacks.isEmpty {
            layoutState.stacks = [SessionStack(title: "Main Stack", sessionIDs: [sessionID], visibleSessionID: sessionID)]
            persistSoon()
            return
        }

        var stack = layoutState.stacks[0]
        if !stack.sessionIDs.contains(sessionID) {
            stack.sessionIDs.append(sessionID)
            if stack.visibleSessionID == nil {
                stack.visibleSessionID = sessionID
            }
            layoutState.stacks[0] = stack
            persistSoon()
        }
    }

    func showStackedSession(_ sessionID: UUID) {
        guard let stackIndex = layoutState.stacks.firstIndex(where: { $0.sessionIDs.contains(sessionID) }) else { return }
        layoutState.stacks[stackIndex].visibleSessionID = sessionID
        sessionService.focusSession(sessionID)
        persistSoon()
    }

    func setVisibleSession(_ sessionID: UUID, inStack stackID: UUID) {
        guard let stackIndex = layoutState.stacks.firstIndex(where: { $0.id == stackID }) else { return }
        guard layoutState.stacks[stackIndex].sessionIDs.contains(sessionID) else { return }
        layoutState.stacks[stackIndex].visibleSessionID = sessionID
        sessionService.focusSession(sessionID)
        persistSoon()
    }

    func isSessionVisibleInStackContext(_ sessionID: UUID) -> Bool {
        for stack in layoutState.stacks where stack.sessionIDs.contains(sessionID) {
            return stack.visibleSessionID == nil || stack.visibleSessionID == sessionID
        }
        return true
    }

    func unstackSession(_ sessionID: UUID) {
        guard !layoutState.stacks.isEmpty else { return }
        var stack = layoutState.stacks[0]
        stack.sessionIDs.removeAll { $0 == sessionID }
        if stack.visibleSessionID == sessionID {
            stack.visibleSessionID = stack.sessionIDs.first
        }
        layoutState.stacks[0] = stack
        persistSoon()
    }

    func toggleFocusMode() {
        layoutState.focusModeEnabled.toggle()
        persistSoon()
    }

    func setFocusedSession(_ sessionID: UUID?) {
        layoutState.focusedSessionID = sessionID
        persistSoon()
    }

    func refreshVibeTools() {
        if let shellPool {
            if shellPool.isWarmed {
                vibeTools = shellPool.cachedTools
            }
            shellPool.refreshTools()
            return
        }

        // Fallback path for tests or isolated service usage without a shell pool.
        vibeTools = discoveryService.discoverInstalledTools()
    }

    func installedVibeTool(withID id: String?) -> VibeCLITool? {
        vibeTools.first(where: { $0.id == id && $0.isInstalled })
    }

    func launchTool(_ toolID: String, in sessionID: UUID) throws {
        try launchService.launch(toolID: toolID, in: sessionID, sessionService: sessionService)
        let message = "Launched \(toolID) in session."
        addQueueItem(
            sessionID: sessionID,
            category: .informational,
            title: "Vibe Tool Started",
            subtitle: message,
            relatedObjectID: nil
        )
    }

    func launchDefaultToolIfConfigured(in sessionID: UUID, settings: AppSettings, respectToggle: Bool = true) {
        if respectToggle, !settings.autoLaunchDefaultVibeToolOnCmdN {
            return
        }
        guard let toolID = settings.defaultVibeToolID else { return }
        do {
            try launchTool(toolID, in: sessionID)
        } catch {
            sessionService.postStatusMessage(error.localizedDescription, for: sessionID)
            addQueueItem(
                sessionID: sessionID,
                category: .error,
                title: "Default Tool Launch Failed",
                subtitle: error.localizedDescription,
                relatedObjectID: nil
            )
        }
    }

    func branchCompareRepoPaths() -> [String] {
        let uniqueRepoPaths = Set(sessionService.sessions.compactMap(\.repoPath))
        return uniqueRepoPaths.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    func localBranches(for repoPath: String) async -> [String] {
        do {
            let gitService = GitService()
            return try await gitService.localBranches(repoPath: repoPath)
        } catch {
            return []
        }
    }

    func presentHandoffComposer(sourceSessionID: UUID, checkpointID: UUID? = nil) {
        guard sessionService.sessions.contains(where: { $0.id == sourceSessionID }) else { return }
        let checkpoint = checkpointID.flatMap { id in checkpoints.first(where: { $0.id == id }) }
        activeHandoffComposer = HandoffComposerDraft(
            sourceSessionID: sourceSessionID,
            targetType: .selfSession,
            checkpointID: checkpointID,
            title: checkpoint.map { "Handoff: \($0.title)" } ?? "Handoff",
            summary: checkpoint?.summary ?? ""
        )
    }

    func dismissHandoffComposer() {
        activeHandoffComposer = nil
    }

    func submitHandoffComposer(_ draft: HandoffComposerDraft) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = draft.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !summary.isEmpty else { return }

        let risks = parseListText(draft.risksText)
        let nextActions = parseListText(draft.nextActionsText)

        let targetSessionID: UUID?
        switch draft.targetType {
        case .selfSession:
            targetSessionID = draft.sourceSessionID
        case .otherSession:
            targetSessionID = draft.targetSessionID
        case .reviewQueue:
            targetSessionID = draft.sourceSessionID
        }

        let handoff = createHandoff(
            sourceSessionID: draft.sourceSessionID,
            targetSessionID: targetSessionID,
            checkpointID: draft.checkpointID,
            title: title,
            summary: summary,
            risks: risks,
            nextActions: nextActions
        )

        if draft.targetType == .reviewQueue {
            let checkpoint = draft.checkpointID.flatMap { id in checkpoints.first(where: { $0.id == id }) }
            let review = createReviewRequest(
                sourceSessionID: draft.sourceSessionID,
                checkpointID: checkpoint?.id,
                summary: checkpoint?.summary ?? summary,
                changedFiles: checkpoint?.changedFiles ?? [],
                diffStat: checkpoint?.diffStat,
                testSummary: checkpoint?.testSummary
            )
            updateHandoffStatus(id: handoff.id, status: .accepted)
            selectedReviewID = review.id
            openRailSurface(.review)
        } else {
            selectedHandoffID = handoff.id
            openRailSurface(.handoffs)
        }

        activeHandoffComposer = nil
    }

}
