import Foundation
import XCTest
@testable import idx0

@MainActor
final class WorkflowServiceTests: XCTestCase {
    func testLegacyAttentionItemsMigrateIntoQueueWithCategoryMapping() throws {
        let root = try makeTempRoot(prefix: "idx0-workflow-migration")
        defer { try? FileManager.default.removeItem(at: root) }

        let services = try makeServices(root: root, legacyAttentionItems: [
            AttentionItem(id: UUID(), sessionID: UUID(), reason: .needsInput, message: "needs", createdAt: Date(), isResolved: false),
            AttentionItem(id: UUID(), sessionID: UUID(), reason: .completed, message: "done", createdAt: Date(), isResolved: true),
            AttentionItem(id: UUID(), sessionID: UUID(), reason: .error, message: "err", createdAt: Date(), isResolved: false),
            AttentionItem(id: UUID(), sessionID: UUID(), reason: .notification, message: "info", createdAt: Date(), isResolved: false)
        ])

        let categories = services.workflowService.queueItems.map(\.category)
        XCTAssertEqual(categories, [.blocked, .completed, .error, .informational])
        XCTAssertEqual(services.workflowService.queueItems.map(\.isResolved), [false, true, false, false])
    }

    func testAgentEventDedupesAndResolvesBySessionIDThenActiveProjectTitle() async throws {
        let root = try makeTempRoot(prefix: "idx0-workflow-events")
        defer { try? FileManager.default.removeItem(at: root) }

        let services = try makeServices(root: root)
        let sessionA = try await services.sessionService.createSession(from: SessionCreationRequest(
            title: "Worker",
            repoPath: root.appendingPathComponent("repo-a", isDirectory: true).path,
            createWorktree: false
        )).session
        let sessionB = try await services.sessionService.createSession(from: SessionCreationRequest(
            title: "Worker",
            repoPath: root.appendingPathComponent("repo-b", isDirectory: true).path,
            createWorktree: false
        )).session
        services.sessionService.focusSession(sessionA.id)

        let byTitle = AgentEventEnvelope(
            schemaVersion: 1,
            eventID: UUID(),
            sessionID: nil,
            sessionTitleHint: "Worker",
            timestamp: Date(),
            eventType: .progress,
            payload: .object(["summary": .string("from title")])
        )

        try services.workflowService.ingestAgentEvent(byTitle)
        XCTAssertEqual(services.workflowService.unresolvedQueueItems.first?.sessionID, sessionA.id)

        XCTAssertThrowsError(try services.workflowService.ingestAgentEvent(byTitle)) { error in
            guard case WorkflowServiceError.duplicateEvent = error else {
                return XCTFail("Expected duplicate event error, got: \(error)")
            }
        }

        let byID = AgentEventEnvelope(
            schemaVersion: 1,
            eventID: UUID(),
            sessionID: sessionB.id,
            sessionTitleHint: "Wrong Title",
            timestamp: Date(),
            eventType: .progress,
            payload: .object(["summary": .string("from id")])
        )
        try services.workflowService.ingestAgentEvent(byID)
        XCTAssertTrue(services.workflowService.queueItems.contains(where: { $0.sessionID == sessionB.id && $0.subtitle == "from id" }))
    }

    func testHandoffReviewApprovalTransitionsUpdateQueueState() async throws {
        let root = try makeTempRoot(prefix: "idx0-workflow-transitions")
        defer { try? FileManager.default.removeItem(at: root) }

        let services = try makeServices(root: root)
        let session = try await services.sessionService.createSession(from: SessionCreationRequest(title: "Worker")).session

        let handoff = services.workflowService.createHandoff(
            sourceSessionID: session.id,
            targetSessionID: nil,
            checkpointID: nil,
            title: "handoff",
            summary: "summary",
            risks: [],
            nextActions: []
        )
        XCTAssertTrue(services.workflowService.queueItems.contains(where: { $0.relatedObjectID == handoff.id && !$0.isResolved }))
        services.workflowService.updateHandoffStatus(id: handoff.id, status: .resolved)
        XCTAssertTrue(services.workflowService.queueItems.contains(where: { $0.relatedObjectID == handoff.id && $0.isResolved }))

        let review = services.workflowService.createReviewRequest(
            sourceSessionID: session.id,
            checkpointID: nil,
            summary: "review",
            changedFiles: [],
            diffStat: nil,
            testSummary: nil
        )
        XCTAssertTrue(services.workflowService.queueItems.contains(where: { $0.relatedObjectID == review.id && !$0.isResolved }))
        try services.workflowService.setReviewStatus(id: review.id, status: .approved)
        XCTAssertTrue(services.workflowService.queueItems.contains(where: { $0.relatedObjectID == review.id && $0.isResolved }))

        let approval = services.workflowService.createApprovalRequest(
            sessionID: session.id,
            title: "Approval",
            summary: "Need approval",
            requestedAction: "Run deploy",
            scopeDescription: nil
        )
        try services.workflowService.respondToApproval(id: approval.id, status: .deferred)
        XCTAssertTrue(services.workflowService.queueItems.contains(where: { $0.relatedObjectID == approval.id && !$0.isResolved }))
        try services.workflowService.respondToApproval(id: approval.id, status: .approved)
        XCTAssertTrue(services.workflowService.queueItems.contains(where: { $0.relatedObjectID == approval.id && $0.isResolved }))
    }

    func testCompareBuildsResultForCheckpointAndSessionInputs() async throws {
        let root = try makeTempRoot(prefix: "idx0-workflow-compare")
        defer { try? FileManager.default.removeItem(at: root) }

        let services = try makeServices(root: root)
        let sessionA = try await services.sessionService.createSession(from: SessionCreationRequest(title: "Left")).session
        let sessionB = try await services.sessionService.createSession(from: SessionCreationRequest(title: "Right")).session

        let checkpointA = try await services.workflowService.createManualCheckpoint(
            sessionID: sessionA.id,
            title: "Checkpoint A",
            summary: "Summary A",
            requestReview: false
        )
        let checkpointB = try await services.workflowService.createManualCheckpoint(
            sessionID: sessionB.id,
            title: "Checkpoint B",
            summary: "Summary B",
            requestReview: false
        )

        let checkpointCompare = await services.workflowService.compare(.checkpoint(checkpointA.id), .checkpoint(checkpointB.id))
        XCTAssertEqual(checkpointCompare?.leftTitle, "Checkpoint A")
        XCTAssertEqual(checkpointCompare?.rightTitle, "Checkpoint B")
        XCTAssertEqual(checkpointCompare?.leftSummary, "Summary A")
        XCTAssertEqual(checkpointCompare?.rightSummary, "Summary B")

        let sessionCompare = await services.workflowService.compare(.session(sessionA.id), .session(sessionB.id))
        XCTAssertEqual(sessionCompare?.leftTitle, "Left")
        XCTAssertEqual(sessionCompare?.rightTitle, "Right")
        XCTAssertEqual(sessionCompare?.leftSourceSessionID, sessionA.id)
        XCTAssertEqual(sessionCompare?.rightSourceSessionID, sessionB.id)
    }

    func testQueueJumpNavigatesToReviewAndCheckpointSelections() async throws {
        let root = try makeTempRoot(prefix: "idx0-workflow-queue-jump")
        defer { try? FileManager.default.removeItem(at: root) }

        let services = try makeServices(root: root)
        let session = try await services.sessionService.createSession(from: SessionCreationRequest(title: "Worker")).session

        let checkpoint = try await services.workflowService.createManualCheckpoint(
            sessionID: session.id,
            title: "Checkpoint",
            summary: "Summary",
            requestReview: false
        )
        let review = services.workflowService.createReviewRequest(
            sourceSessionID: session.id,
            checkpointID: checkpoint.id,
            summary: "Review me",
            changedFiles: checkpoint.changedFiles,
            diffStat: checkpoint.diffStat,
            testSummary: checkpoint.testSummary
        )

        guard let reviewQueueItem = services.workflowService.queueItems.first(where: { $0.relatedObjectID == review.id }) else {
            XCTFail("Expected review queue item")
            return
        }
        services.workflowService.navigateFromQueueItem(reviewQueueItem)
        XCTAssertEqual(services.workflowService.selectedRailSurface, .review)
        XCTAssertEqual(services.workflowService.selectedReviewID, review.id)

        guard let checkpointQueueItem = services.workflowService.queueItems.first(where: { $0.relatedObjectID == checkpoint.id }) else {
            XCTFail("Expected checkpoint queue item")
            return
        }
        services.workflowService.navigateFromQueueItem(checkpointQueueItem)
        XCTAssertEqual(services.workflowService.selectedRailSurface, .checkpoints)
        XCTAssertEqual(services.workflowService.selectedCheckpointID, checkpoint.id)
    }

    func testReviewQueueHandoffCreatesReviewAndAcceptsHandoff() async throws {
        let root = try makeTempRoot(prefix: "idx0-workflow-handoff-review-queue")
        defer { try? FileManager.default.removeItem(at: root) }

        let services = try makeServices(root: root)
        let session = try await services.sessionService.createSession(from: SessionCreationRequest(title: "Worker")).session
        let checkpoint = try await services.workflowService.createManualCheckpoint(
            sessionID: session.id,
            title: "Handoff Checkpoint",
            summary: "Checkpoint summary",
            requestReview: false
        )

        services.workflowService.presentHandoffComposer(sourceSessionID: session.id, checkpointID: checkpoint.id)
        guard var draft = services.workflowService.activeHandoffComposer else {
            XCTFail("Expected handoff composer draft")
            return
        }
        draft.targetType = .reviewQueue
        draft.title = "Queue handoff"
        draft.summary = "Please review this handoff"
        draft.risksText = "risk-a,risk-b"
        draft.nextActionsText = "next-a,next-b"
        services.workflowService.submitHandoffComposer(draft)

        guard let handoff = services.workflowService.handoffs.sorted(by: { $0.createdAt > $1.createdAt }).first else {
            XCTFail("Expected handoff")
            return
        }
        XCTAssertEqual(handoff.status, .accepted)
        XCTAssertEqual(handoff.checkpointID, checkpoint.id)

        guard let review = services.workflowService.reviews.sorted(by: { $0.createdAt > $1.createdAt }).first else {
            XCTFail("Expected review request")
            return
        }
        XCTAssertEqual(review.checkpointID, checkpoint.id)
        XCTAssertEqual(services.workflowService.selectedRailSurface, .review)
        XCTAssertEqual(services.workflowService.selectedReviewID, review.id)

        XCTAssertTrue(
            services.workflowService.queueItems.contains(where: {
                $0.relatedObjectID == handoff.id && $0.isResolved
            })
        )
    }

    func testBranchCompareBuildsOverlapAndDifferenceFileLists() async throws {
        let root = try makeTempRoot(prefix: "idx0-workflow-branch-compare")
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        _ = try git(["init"], at: repo)
        _ = try git(["config", "user.email", "idx0-tests@example.com"], at: repo)
        _ = try git(["config", "user.name", "idx0-tests"], at: repo)

        let common = repo.appendingPathComponent("common.txt")
        try "base\n".write(to: common, atomically: true, encoding: .utf8)
        _ = try git(["add", "."], at: repo)
        _ = try git(["commit", "-m", "base"], at: repo)
        let baseSHA = try git(["rev-parse", "HEAD"], at: repo).trimmingCharacters(in: .whitespacesAndNewlines)

        _ = try git(["checkout", "-b", "left"], at: repo)
        try "left\n".write(to: common, atomically: true, encoding: .utf8)
        try "left only\n".write(
            to: repo.appendingPathComponent("left-only.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = try git(["add", "."], at: repo)
        _ = try git(["commit", "-m", "left changes"], at: repo)

        _ = try git(["checkout", "-b", "right", baseSHA], at: repo)
        try "right\n".write(to: common, atomically: true, encoding: .utf8)
        try "right only\n".write(
            to: repo.appendingPathComponent("right-only.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = try git(["add", "."], at: repo)
        _ = try git(["commit", "-m", "right changes"], at: repo)

        let services = try makeServices(root: root)
        _ = try await services.sessionService.createSession(from: SessionCreationRequest(
            title: "Repo Worker",
            repoPath: repo.path,
            createWorktree: false
        )).session

        let result = await services.workflowService.compareBranches(
            repoPath: repo.path,
            leftBranch: "left",
            rightBranch: "right"
        )

        XCTAssertEqual(result?.leftTitle, "left")
        XCTAssertEqual(result?.rightTitle, "right")
        XCTAssertEqual(Set(result?.overlapPaths ?? []), Set(["common.txt"]))
        XCTAssertEqual(Set(result?.leftOnlyPaths ?? []), Set(["left-only.txt"]))
        XCTAssertEqual(Set(result?.rightOnlyPaths ?? []), Set(["right-only.txt"]))
    }

    private func makeTempRoot(prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeServices(root: URL, legacyAttentionItems: [AttentionItem] = []) throws -> (sessionService: SessionService, workflowService: WorkflowService) {
        let paths = FileSystemPaths(
            appSupportDirectory: root,
            sessionsFile: root.appendingPathComponent("sessions.json"),
            projectsFile: root.appendingPathComponent("projects.json"),
            inboxFile: root.appendingPathComponent("inbox.json"),
            settingsFile: root.appendingPathComponent("settings.json"),
            runDirectory: root.appendingPathComponent("run", isDirectory: true),
            tempDirectory: root.appendingPathComponent("temp", isDirectory: true),
            worktreesDirectory: root.appendingPathComponent("worktrees", isDirectory: true)
        )
        try paths.ensureDirectories()

        let sessionService = SessionService(
            sessionStore: SessionStore(url: paths.sessionsFile),
            projectStore: ProjectStore(url: paths.projectsFile),
            inboxStore: InboxStore(url: paths.inboxFile),
            settingsStore: SettingsStore(url: paths.settingsFile),
            worktreeService: WorktreeService(gitService: GitService(), paths: paths),
            launcherDirectory: root.appendingPathComponent("launchers", isDirectory: true),
            host: .shared
        )

        let workflowService = WorkflowService(
            sessionService: sessionService,
            checkpointStore: CheckpointStore(url: paths.checkpointsFile),
            handoffStore: HandoffStore(url: paths.handoffsFile),
            reviewStore: ReviewStore(url: paths.reviewsFile),
            approvalStore: ApprovalStore(url: paths.approvalsFile),
            queueStore: QueueStore(url: paths.queueFile),
            timelineStore: TimelineStore(url: paths.timelineFile),
            layoutStore: LayoutStore(url: paths.layoutFile),
            agentEventStore: AgentEventStore(url: paths.agentEventsFile),
            legacyAttentionItems: legacyAttentionItems
        )

        return (sessionService, workflowService)
    }

    private func git(_ arguments: [String], at path: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = path

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let error = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "WorkflowServiceTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git \(arguments.joined(separator: " ")) failed: \(error)"]
            )
        }
        return output
    }
}
