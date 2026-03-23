import Foundation

extension WorkflowService {
    func ingestAgentEvent(_ envelope: AgentEventEnvelope) throws {
        guard envelope.schemaVersion == 1 else {
            throw WorkflowServiceError.unsupportedSchemaVersion(envelope.schemaVersion)
        }
        guard !handledEventIDs.contains(envelope.eventID) else {
            throw WorkflowServiceError.duplicateEvent
        }

        guard let sessionID = resolveSessionID(for: envelope) else {
            throw WorkflowServiceError.unresolvedSession
        }

        switch envelope.eventType {
        case .progress:
            addQueueItem(
                sessionID: sessionID,
                category: .informational,
                title: "Progress update",
                subtitle: envelope.payload.objectValue?["summary"]?.stringValue,
                relatedObjectID: nil
            )
            addTimeline(sessionID: sessionID, type: .statusProgress, title: "Progress update", relatedObjectID: nil)
        case .checkpoint:
            let title = envelope.payload.objectValue?["title"]?.stringValue ?? "Agent checkpoint"
            let summary = envelope.payload.objectValue?["summary"]?.stringValue ?? "Checkpoint emitted by harness."
            let changedFiles = parseChangedFiles(from: envelope.payload.objectValue?["changedFiles"])
            let checkpoint = Checkpoint(
                id: UUID(),
                sessionID: sessionID,
                repoPath: sessionService.sessions.first(where: { $0.id == sessionID })?.repoPath,
                branchName: sessionService.sessions.first(where: { $0.id == sessionID })?.branchName,
                worktreePath: sessionService.sessions.first(where: { $0.id == sessionID })?.worktreePath,
                title: title,
                summary: summary,
                commitSHA: envelope.payload.objectValue?["commitSHA"]?.stringValue,
                changedFiles: changedFiles,
                diffStat: parseDiffStat(from: envelope.payload.objectValue?["diffStat"]),
                testSummary: parseTestSummary(from: envelope.payload.objectValue?["testSummary"]),
                createdAt: envelope.timestamp,
                source: .agentEvent
            )
            checkpoints.append(checkpoint)
            selectedCheckpointID = checkpoint.id
            addQueueItem(
                sessionID: sessionID,
                category: .informational,
                title: "Checkpoint created",
                subtitle: title,
                relatedObjectID: checkpoint.id
            )
            addTimeline(sessionID: sessionID, type: .checkpointCreated, title: title, relatedObjectID: checkpoint.id)
        case .handoff:
            _ = createHandoff(
                sourceSessionID: sessionID,
                targetSessionID: parseUUID(from: envelope.payload.objectValue?["targetSessionID"]),
                checkpointID: parseUUID(from: envelope.payload.objectValue?["checkpointID"]),
                title: envelope.payload.objectValue?["title"]?.stringValue ?? "Agent handoff",
                summary: envelope.payload.objectValue?["summary"]?.stringValue ?? "Handoff from harness.",
                risks: parseStringArray(from: envelope.payload.objectValue?["risks"]),
                nextActions: parseStringArray(from: envelope.payload.objectValue?["nextActions"])
            )
        case .reviewRequest:
            _ = createReviewRequest(
                sourceSessionID: sessionID,
                checkpointID: parseUUID(from: envelope.payload.objectValue?["checkpointID"]),
                summary: envelope.payload.objectValue?["summary"]?.stringValue ?? "Review requested by harness.",
                changedFiles: parseChangedFiles(from: envelope.payload.objectValue?["changedFiles"]),
                diffStat: parseDiffStat(from: envelope.payload.objectValue?["diffStat"]),
                testSummary: parseTestSummary(from: envelope.payload.objectValue?["testSummary"])
            )
        case .approvalRequest:
            _ = createApprovalRequest(
                sessionID: sessionID,
                title: envelope.payload.objectValue?["title"]?.stringValue ?? "Approval requested",
                summary: envelope.payload.objectValue?["summary"]?.stringValue ?? "Harness requested approval.",
                requestedAction: envelope.payload.objectValue?["requestedAction"]?.stringValue ?? "Review requested action",
                scopeDescription: envelope.payload.objectValue?["scopeDescription"]?.stringValue
            )
        case .completed:
            addQueueItem(
                sessionID: sessionID,
                category: .completed,
                title: "Completed",
                subtitle: envelope.payload.objectValue?["summary"]?.stringValue,
                relatedObjectID: nil
            )
            addTimeline(sessionID: sessionID, type: .statusCompleted, title: "Completed", relatedObjectID: nil)
        case .blocked:
            addQueueItem(
                sessionID: sessionID,
                category: .blocked,
                title: "Blocked",
                subtitle: envelope.payload.objectValue?["summary"]?.stringValue,
                relatedObjectID: nil
            )
            addTimeline(sessionID: sessionID, type: .statusBlocked, title: "Blocked", relatedObjectID: nil)
        case .error:
            addQueueItem(
                sessionID: sessionID,
                category: .error,
                title: "Error",
                subtitle: envelope.payload.objectValue?["summary"]?.stringValue,
                relatedObjectID: nil
            )
            addTimeline(sessionID: sessionID, type: .statusError, title: "Errored", relatedObjectID: nil)
        }

        handledEventIDs.insert(envelope.eventID)
        persistSoon()
    }

    func recordSessionCreated(_ session: Session) {
        addTimeline(
            sessionID: session.id,
            type: .sessionCreated,
            title: "Session created",
            relatedObjectID: nil
        )
    }

    func recordSessionLaunched(_ sessionID: UUID) {
        addTimeline(sessionID: sessionID, type: .sessionLaunched, title: "Session launched", relatedObjectID: nil)
    }

    func recordSessionClosed(_ sessionID: UUID) {
        addTimeline(sessionID: sessionID, type: .sessionClosed, title: "Session closed", relatedObjectID: nil)
    }

    func recordSessionCompleted(_ sessionID: UUID, message: String?) {
        // Only log to timeline — routine terminal exits don't need queue items
        addTimeline(sessionID: sessionID, type: .statusCompleted, title: "Terminal completed", relatedObjectID: nil)
    }

    func recordSessionError(_ sessionID: UUID, message: String?) {
        addQueueItem(
            sessionID: sessionID,
            category: .error,
            title: "Terminal error",
            subtitle: message,
            relatedObjectID: nil
        )
        addTimeline(sessionID: sessionID, type: .statusError, title: "Terminal error", relatedObjectID: nil)
    }

    func recordSessionNeedsInput(_ sessionID: UUID, message: String?) {
        // Deduplicate: don't add if there's already an unresolved approval-needed item for this session
        let alreadyQueued = queueItems.contains { item in
            item.sessionID == sessionID && item.category == .approvalNeeded && !item.isResolved
        }
        guard !alreadyQueued else { return }

        addQueueItem(
            sessionID: sessionID,
            category: .approvalNeeded,
            title: "Approval needed",
            subtitle: message,
            relatedObjectID: nil
        )
        addTimeline(sessionID: sessionID, type: .statusNeedsInput, title: "Approval needed", relatedObjectID: nil)
    }

    func resolveApprovalItems(for sessionID: UUID) {
        var changed = false
        for index in queueItems.indices {
            if queueItems[index].sessionID == sessionID
                && queueItems[index].category == .approvalNeeded
                && !queueItems[index].isResolved {
                queueItems[index].isResolved = true
                changed = true
            }
        }
        if changed { persistSoon() }
    }

    func prepareForTermination() {
        persistNow()
    }
}
