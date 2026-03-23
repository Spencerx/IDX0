import Foundation

extension WorkflowService {
    func createManualCheckpoint(
        sessionID: UUID,
        title: String,
        summary: String,
        requestReview: Bool,
        source: CheckpointSource = .manual
    ) async throws -> Checkpoint {
        guard let session = sessionService.sessions.first(where: { $0.id == sessionID }) else {
            throw WorkflowServiceError.sessionNotFound
        }

        let gitSnapshot = try await makeGitSnapshot(for: session)
        let checkpoint = Checkpoint(
            id: UUID(),
            sessionID: sessionID,
            repoPath: session.repoPath,
            branchName: gitSnapshot.branchName ?? session.branchName,
            worktreePath: session.worktreePath,
            title: title,
            summary: summary,
            commitSHA: gitSnapshot.commitSHA,
            changedFiles: gitSnapshot.changedFiles,
            diffStat: gitSnapshot.diffStat,
            testSummary: nil,
            createdAt: Date(),
            source: source
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
        addTimeline(
            sessionID: sessionID,
            type: .checkpointCreated,
            title: "Checkpoint: \(title)",
            relatedObjectID: checkpoint.id
        )

        if requestReview {
            _ = createReviewRequest(
                sourceSessionID: sessionID,
                checkpointID: checkpoint.id,
                summary: summary,
                changedFiles: checkpoint.changedFiles,
                diffStat: checkpoint.diffStat,
                testSummary: checkpoint.testSummary
            )
        }

        persistSoon()
        return checkpoint
    }

    func createHandoff(
        sourceSessionID: UUID,
        targetSessionID: UUID?,
        checkpointID: UUID?,
        title: String,
        summary: String,
        risks: [String],
        nextActions: [String]
    ) -> Handoff {
        let handoff = Handoff(
            id: UUID(),
            sourceSessionID: sourceSessionID,
            targetSessionID: targetSessionID,
            checkpointID: checkpointID,
            title: title,
            summary: summary,
            risks: risks,
            nextActions: nextActions,
            createdAt: Date(),
            status: .pending
        )
        handoffs.append(handoff)
        selectedHandoffID = handoff.id

        let target = targetSessionID ?? sourceSessionID
        addQueueItem(
            sessionID: target,
            category: .blocked,
            title: "Handoff: \(title)",
            subtitle: summary,
            relatedObjectID: handoff.id
        )

        addTimeline(
            sessionID: sourceSessionID,
            type: .handoffCreated,
            title: "Handoff created",
            relatedObjectID: handoff.id
        )
        if let targetSessionID {
            addTimeline(
                sessionID: targetSessionID,
                type: .handoffCreated,
                title: "Handoff received",
                relatedObjectID: handoff.id
            )
        }
        persistSoon()
        return handoff
    }

    func updateHandoffStatus(id: UUID, status: HandoffStatus) {
        guard let index = handoffs.firstIndex(where: { $0.id == id }) else { return }
        handoffs[index].status = status
        let timelineSessionID = handoffs[index].targetSessionID ?? handoffs[index].sourceSessionID
        if status == .accepted || status == .resolved {
            queueItems = queueService.resolveForRelatedObject(relatedObjectID: id, in: queueItems)
        }
        let title: String
        switch status {
        case .pending:
            title = "Handoff pending"
        case .accepted:
            title = "Handoff accepted"
        case .resolved:
            title = "Handoff resolved"
        }
        addTimeline(
            sessionID: timelineSessionID,
            type: .handoffUpdated,
            title: title,
            relatedObjectID: id
        )
        persistSoon()
    }

    func createReviewRequest(
        sourceSessionID: UUID,
        checkpointID: UUID?,
        summary: String,
        changedFiles: [ChangedFileSummary],
        diffStat: DiffStat?,
        testSummary: TestSummary?
    ) -> ReviewRequest {
        let review = ReviewRequest(
            id: UUID(),
            sourceSessionID: sourceSessionID,
            checkpointID: checkpointID,
            createdAt: Date(),
            summary: summary,
            changedFiles: changedFiles,
            diffStat: diffStat,
            testSummary: testSummary,
            status: .open
        )
        reviews.append(review)
        selectedReviewID = review.id
        addQueueItem(
            sessionID: sourceSessionID,
            category: .reviewRequested,
            title: "Review requested",
            subtitle: summary,
            relatedObjectID: review.id
        )
        addTimeline(
            sessionID: sourceSessionID,
            type: .reviewRequested,
            title: "Review requested",
            relatedObjectID: review.id
        )
        persistSoon()
        return review
    }

    func setReviewStatus(id: UUID, status: ReviewStatus) throws {
        guard let index = reviews.firstIndex(where: { $0.id == id }) else {
            throw WorkflowServiceError.reviewNotFound
        }
        reviews[index].status = status
        let sessionID = reviews[index].sourceSessionID

        switch status {
        case .approved:
            queueItems = queueService.resolveForRelatedObject(relatedObjectID: id, in: queueItems)
            addTimeline(
                sessionID: sessionID,
                type: .reviewUpdated,
                title: "Review approved",
                relatedObjectID: id
            )
        case .changesRequested:
            ensureUnresolvedQueueItem(
                sessionID: sessionID,
                category: .reviewRequested,
                title: "Changes requested",
                subtitle: reviews[index].summary,
                relatedObjectID: id
            )
            addTimeline(
                sessionID: sessionID,
                type: .reviewUpdated,
                title: "Review changes requested",
                relatedObjectID: id
            )
        case .deferred:
            ensureUnresolvedQueueItem(
                sessionID: sessionID,
                category: .informational,
                title: "Review deferred",
                subtitle: reviews[index].summary,
                relatedObjectID: id
            )
            addTimeline(
                sessionID: sessionID,
                type: .reviewUpdated,
                title: "Review deferred",
                relatedObjectID: id
            )
        case .open:
            ensureUnresolvedQueueItem(
                sessionID: sessionID,
                category: .reviewRequested,
                title: "Review requested",
                subtitle: reviews[index].summary,
                relatedObjectID: id
            )
            addTimeline(
                sessionID: sessionID,
                type: .reviewUpdated,
                title: "Review reopened",
                relatedObjectID: id
            )
            break
        }
        persistSoon()
    }

    func createApprovalRequest(
        sessionID: UUID,
        title: String,
        summary: String,
        requestedAction: String,
        scopeDescription: String?
    ) -> ApprovalRequest {
        let approval = ApprovalRequest(
            id: UUID(),
            sessionID: sessionID,
            createdAt: Date(),
            title: title,
            summary: summary,
            requestedAction: requestedAction,
            scopeDescription: scopeDescription,
            status: .pending
        )
        approvals.append(approval)
        addQueueItem(
            sessionID: sessionID,
            category: .approvalNeeded,
            title: title,
            subtitle: summary,
            relatedObjectID: approval.id
        )
        addTimeline(
            sessionID: sessionID,
            type: .approvalRequested,
            title: title,
            relatedObjectID: approval.id
        )
        postApprovalNotificationIfNeeded(sessionID: sessionID, title: title, summary: summary)
        persistSoon()
        return approval
    }

    func respondToApproval(id: UUID, status: ApprovalStatus) throws {
        guard let index = approvals.firstIndex(where: { $0.id == id }) else {
            throw WorkflowServiceError.approvalNotFound
        }
        approvals[index].status = status
        let sessionID = approvals[index].sessionID
        if status == .approved || status == .denied {
            queueItems = queueService.resolveForRelatedObject(relatedObjectID: id, in: queueItems)
        }
        if status == .deferred {
            ensureUnresolvedQueueItem(
                sessionID: sessionID,
                category: .approvalNeeded,
                title: approvals[index].title,
                subtitle: "Deferred: \(approvals[index].summary)",
                relatedObjectID: id
            )
        }
        let title: String
        switch status {
        case .pending:
            title = "Approval pending"
        case .approved:
            title = "Approval approved"
        case .denied:
            title = "Approval denied"
        case .deferred:
            title = "Approval deferred"
        }
        addTimeline(
            sessionID: sessionID,
            type: .approvalUpdated,
            title: title,
            relatedObjectID: id
        )
        persistSoon()
    }

    func compare(_ left: CompareInput, _ right: CompareInput) async -> CompareResult? {
        guard let leftValue = await compareValue(for: left), let rightValue = await compareValue(for: right) else {
            return nil
        }

        let leftPaths = Set(leftValue.changedFiles.map(\.path))
        let rightPaths = Set(rightValue.changedFiles.map(\.path))
        let overlap = leftPaths.intersection(rightPaths).sorted()
        let leftOnly = leftPaths.subtracting(rightPaths).sorted()
        let rightOnly = rightPaths.subtracting(leftPaths).sorted()

        return CompareResult(
            leftTitle: leftValue.title,
            leftSummary: leftValue.summary,
            leftSourceSessionID: leftValue.sourceSessionID,
            rightTitle: rightValue.title,
            rightSummary: rightValue.summary,
            rightSourceSessionID: rightValue.sourceSessionID,
            leftFiles: leftValue.changedFiles,
            rightFiles: rightValue.changedFiles,
            leftDiffStat: leftValue.diffStat,
            rightDiffStat: rightValue.diffStat,
            leftTestSummary: leftValue.testSummary,
            rightTestSummary: rightValue.testSummary,
            overlapPaths: overlap,
            leftOnlyPaths: leftOnly,
            rightOnlyPaths: rightOnly
        )
    }

    func compareBranches(repoPath: String, leftBranch: String, rightBranch: String) async -> CompareResult? {
        let left = CompareInput.branches(repoPath: repoPath, leftBranch: rightBranch, rightBranch: leftBranch)
        let right = CompareInput.branches(repoPath: repoPath, leftBranch: leftBranch, rightBranch: rightBranch)
        guard let leftValue = await compareValue(for: left), let rightValue = await compareValue(for: right) else {
            return nil
        }

        let leftPaths = Set(leftValue.changedFiles.map(\.path))
        let rightPaths = Set(rightValue.changedFiles.map(\.path))
        let overlap = leftPaths.intersection(rightPaths).sorted()
        let leftOnly = leftPaths.subtracting(rightPaths).sorted()
        let rightOnly = rightPaths.subtracting(leftPaths).sorted()
        let repoName = URL(fileURLWithPath: repoPath).lastPathComponent

        return CompareResult(
            leftTitle: leftBranch,
            leftSummary: repoName,
            leftSourceSessionID: nil,
            rightTitle: rightBranch,
            rightSummary: repoName,
            rightSourceSessionID: nil,
            leftFiles: leftValue.changedFiles,
            rightFiles: rightValue.changedFiles,
            leftDiffStat: leftValue.diffStat,
            rightDiffStat: rightValue.diffStat,
            leftTestSummary: nil,
            rightTestSummary: nil,
            overlapPaths: overlap,
            leftOnlyPaths: leftOnly,
            rightOnlyPaths: rightOnly
        )
    }

}
