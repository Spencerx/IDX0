import AppKit
import Foundation

@MainActor
final class IPCCommandRouter {
    private let sessionService: SessionService
    private let workflowService: WorkflowService
    private let agentEventRouter: AgentEventRouter

    init(
        sessionService: SessionService,
        workflowService: WorkflowService,
        agentEventRouter: AgentEventRouter = AgentEventRouter()
    ) {
        self.sessionService = sessionService
        self.workflowService = workflowService
        self.agentEventRouter = agentEventRouter
    }

    func handle(_ request: IPCRequest) -> IPCResponse {
        switch request.command {
        case IPCCommand.open:
            return handleOpen()

        case IPCCommand.newSession:
            return handleNewSession(request.payload, allowDefaultToolFallback: false)

        case IPCCommand.newSessionWithTool:
            return handleNewSession(request.payload, allowDefaultToolFallback: true)

        case IPCCommand.focusSession:
            return handleFocusSession(request.payload)

        case IPCCommand.listSessions:
            return handleListSessions()

        case IPCCommand.createCheckpoint:
            return handleCreateCheckpoint(request.payload)

        case IPCCommand.createHandoff:
            return handleCreateHandoff(request.payload)

        case IPCCommand.requestReview:
            return handleRequestReview(request.payload)

        case IPCCommand.listQueue:
            return handleListQueue()

        case IPCCommand.listApprovals:
            return handleListApprovals(request.payload)

        case IPCCommand.listVibeTools:
            return handleListVibeTools()

        case IPCCommand.agentEvent:
            return handleAgentEvent(request.payload)

        case IPCCommand.respondApproval:
            return handleRespondApproval(request.payload)

        case IPCCommand.setReviewStatus:
            return handleSetReviewStatus(request.payload)

        case IPCCommand.markQueueResolved:
            return handleMarkQueueResolved(request.payload)

        case IPCCommand.notify:
            return handleNotify(request.payload)

        default:
            return IPCResponse(success: false, message: "Unknown command '\(request.command)'", data: nil)
        }
    }

    private func handleOpen() -> IPCResponse {
        NSApp.activate(ignoringOtherApps: true)
        return IPCResponse(success: true, message: "IDX0 activated", data: nil)
    }

    private func handleNewSession(_ payload: [String: String], allowDefaultToolFallback: Bool) -> IPCResponse {
        let repoPath = payload["repoPath"]
        let branchName = payload["branchName"]
        let createWorktree = parseBool(payload["createWorktree"])
        let title = payload["title"]
        let toolID = payload["toolID"]
        Task {
            do {
                let created = try await sessionService.createSession(from: SessionCreationRequest(
                    title: title,
                    repoPath: repoPath,
                    createWorktree: createWorktree,
                    branchName: branchName,
                    existingWorktreePath: payload["existingWorktreePath"],
                    shellPath: nil,
                    launchToolID: toolID
                ))
                if let toolID, !toolID.isEmpty {
                    do {
                        try workflowService.launchTool(toolID, in: created.session.id)
                    } catch {
                        sessionService.postStatusMessage(error.localizedDescription, for: created.session.id)
                    }
                } else if allowDefaultToolFallback {
                    workflowService.launchDefaultToolIfConfigured(
                        in: created.session.id,
                        settings: sessionService.settings,
                        respectToggle: false
                    )
                }
            } catch {
                Logger.error("IPC \(allowDefaultToolFallback ? "newSessionWithTool" : "newSession") failed: \(error.localizedDescription)")
            }
        }
        let message = allowDefaultToolFallback ? "Session with tool requested" : "Session creation requested"
        return IPCResponse(success: true, message: message, data: nil)
    }

    private func handleFocusSession(_ payload: [String: String]) -> IPCResponse {
        guard let query = payload["session"], !query.isEmpty else {
            return IPCResponse(success: false, message: "Missing --session value", data: nil)
        }

        let exactID = UUID(uuidString: query)
        if let exactID, sessionService.sessions.contains(where: { $0.id == exactID }) {
            sessionService.focusSession(exactID)
            NSApp.activate(ignoringOtherApps: true)
            return IPCResponse(success: true, message: "Focused session \(exactID.uuidString)", data: nil)
        }

        let matches = sessionService.sessions.filter { session in
            session.title.caseInsensitiveCompare(query) == .orderedSame
                || session.title.localizedCaseInsensitiveContains(query)
        }
        guard !matches.isEmpty else {
            return IPCResponse(success: false, message: "No session matched '\(query)'", data: nil)
        }
        guard matches.count == 1 else {
            return IPCResponse(success: false, message: "Ambiguous session query '\(query)'", data: nil)
        }

        sessionService.focusSession(matches[0].id)
        NSApp.activate(ignoringOtherApps: true)
        return IPCResponse(success: true, message: "Focused '\(matches[0].title)'", data: nil)
    }

    private func handleListSessions() -> IPCResponse {
        var payload: [String: String] = [:]
        for session in sessionService.sessions {
            payload[session.id.uuidString] = session.title
        }
        return IPCResponse(success: true, message: "OK", data: payload)
    }

    private func handleCreateCheckpoint(_ payload: [String: String]) -> IPCResponse {
        guard let query = payload["session"], !query.isEmpty else {
            return IPCResponse(success: false, message: "Missing --session value", data: nil)
        }
        guard let sessionID = resolveSessionID(query) else {
            return IPCResponse(success: false, message: "Unable to resolve session '\(query)'", data: nil)
        }
        let title = payload["title"] ?? "Checkpoint"
        let summary = payload["summary"] ?? "Manual checkpoint"
        let requestReview = parseBool(payload["requestReview"])
        Task {
            do {
                _ = try await workflowService.createManualCheckpoint(
                    sessionID: sessionID,
                    title: title,
                    summary: summary,
                    requestReview: requestReview
                )
            } catch {
                Logger.error("IPC createCheckpoint failed: \(error.localizedDescription)")
            }
        }
        return IPCResponse(success: true, message: "Checkpoint requested", data: nil)
    }

    private func handleCreateHandoff(_ payload: [String: String]) -> IPCResponse {
        guard let query = payload["session"], !query.isEmpty else {
            return IPCResponse(success: false, message: "Missing --session value", data: nil)
        }
        guard let sourceSessionID = resolveSessionID(query) else {
            return IPCResponse(success: false, message: "Unable to resolve session '\(query)'", data: nil)
        }
        let targetSessionID = resolveSessionID(payload["targetSession"] ?? "")
        let checkpointID = UUID(uuidString: payload["checkpointID"] ?? "")
        let title = payload["title"] ?? "Handoff"
        let summary = payload["summary"] ?? "Handoff requested"
        let risks = parseList(payload["risks"])
        let nextActions = parseList(payload["nextActions"])
        _ = workflowService.createHandoff(
            sourceSessionID: sourceSessionID,
            targetSessionID: targetSessionID,
            checkpointID: checkpointID,
            title: title,
            summary: summary,
            risks: risks,
            nextActions: nextActions
        )
        return IPCResponse(success: true, message: "Handoff created", data: nil)
    }

    private func handleRequestReview(_ payload: [String: String]) -> IPCResponse {
        guard let query = payload["session"], !query.isEmpty else {
            return IPCResponse(success: false, message: "Missing --session value", data: nil)
        }
        guard let sourceSessionID = resolveSessionID(query) else {
            return IPCResponse(success: false, message: "Unable to resolve session '\(query)'", data: nil)
        }
        let checkpointID = UUID(uuidString: payload["checkpointID"] ?? "")
        let summary = payload["summary"] ?? "Review requested"
        _ = workflowService.createReviewRequest(
            sourceSessionID: sourceSessionID,
            checkpointID: checkpointID,
            summary: summary,
            changedFiles: [],
            diffStat: nil,
            testSummary: nil
        )
        return IPCResponse(success: true, message: "Review requested", data: nil)
    }

    private func handleListQueue() -> IPCResponse {
        let items = workflowService.unresolvedQueueItems
        let encoded = encodeJSON(items)
        return IPCResponse(success: true, message: "OK", data: ["json": encoded])
    }

    private func handleListApprovals(_ payload: [String: String]) -> IPCResponse {
        var approvals = workflowService.approvals
        if let sessionQuery = payload["session"],
           !sessionQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let sessionID = resolveSessionID(sessionQuery) else {
                return IPCResponse(success: false, message: "Unable to resolve session '\(sessionQuery)'", data: nil)
            }
            approvals = approvals.filter { $0.sessionID == sessionID }
        }
        if let statusRaw = payload["status"],
           !statusRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalized = statusRaw.lowercased()
            guard let status = ApprovalStatus(rawValue: normalized) else {
                return IPCResponse(success: false, message: "Invalid approval status '\(statusRaw)'", data: nil)
            }
            approvals = approvals.filter { $0.status == status }
        }
        approvals.sort { lhs, rhs in
            if lhs.status == .pending, rhs.status != .pending { return true }
            if lhs.status != .pending, rhs.status == .pending { return false }
            return lhs.createdAt > rhs.createdAt
        }
        let encoded = encodeJSON(approvals)
        return IPCResponse(success: true, message: "OK", data: ["json": encoded])
    }

    private func handleListVibeTools() -> IPCResponse {
        workflowService.refreshVibeTools()
        let encoded = encodeJSON(workflowService.vibeTools)
        return IPCResponse(success: true, message: "OK", data: ["json": encoded])
    }

    private func handleAgentEvent(_ payload: [String: String]) -> IPCResponse {
        do {
            let envelope = try agentEventRouter.decodeEnvelope(from: payload)
            try workflowService.ingestAgentEvent(envelope)
            return IPCResponse(success: true, message: "Event ingested", data: nil)
        } catch {
            return IPCResponse(success: false, message: error.localizedDescription, data: nil)
        }
    }

    private func handleRespondApproval(_ payload: [String: String]) -> IPCResponse {
        guard let approvalIDRaw = payload["approvalID"], let approvalID = UUID(uuidString: approvalIDRaw) else {
            return IPCResponse(success: false, message: "Missing approvalID", data: nil)
        }
        guard let statusRaw = payload["status"], let status = ApprovalStatus(rawValue: statusRaw) else {
            return IPCResponse(success: false, message: "Missing or invalid approval status", data: nil)
        }
        do {
            try workflowService.respondToApproval(id: approvalID, status: status)
            return IPCResponse(success: true, message: "Approval updated", data: nil)
        } catch {
            return IPCResponse(success: false, message: error.localizedDescription, data: nil)
        }
    }

    private func handleSetReviewStatus(_ payload: [String: String]) -> IPCResponse {
        guard let reviewIDRaw = payload["reviewID"], let reviewID = UUID(uuidString: reviewIDRaw) else {
            return IPCResponse(success: false, message: "Missing reviewID", data: nil)
        }
        guard let statusRaw = payload["status"], let status = ReviewStatus(rawValue: statusRaw) else {
            return IPCResponse(success: false, message: "Missing or invalid review status", data: nil)
        }
        do {
            try workflowService.setReviewStatus(id: reviewID, status: status)
            return IPCResponse(success: true, message: "Review updated", data: nil)
        } catch {
            return IPCResponse(success: false, message: error.localizedDescription, data: nil)
        }
    }

    private func handleMarkQueueResolved(_ payload: [String: String]) -> IPCResponse {
        guard let queueIDRaw = payload["queueID"], let queueID = UUID(uuidString: queueIDRaw) else {
            return IPCResponse(success: false, message: "Missing queueID", data: nil)
        }
        workflowService.markQueueItemResolved(queueID)
        return IPCResponse(success: true, message: "Queue item resolved", data: nil)
    }

    private func handleNotify(_ payload: [String: String]) -> IPCResponse {
        guard let sessionID = UUID(uuidString: payload["sessionID"] ?? "") else {
            return IPCResponse(success: false, message: "Missing or invalid sessionID", data: nil)
        }
        let title = payload["title"] ?? "Activity"
        let summary = payload["summary"]
        let category = QueueItemCategory(rawValue: payload["category"] ?? "informational") ?? .informational
        workflowService.addNotification(
            sessionID: sessionID,
            category: category,
            title: title,
            subtitle: summary
        )
        if let activityType = payload["activity"] {
            applyAgentActivity(
                sessionID: sessionID,
                title: title,
                summary: summary,
                activityType: activityType,
                activityDescription: payload["activityDescription"]
            )
        }
        return IPCResponse(success: true, message: "Notification created", data: nil)
    }

    private func applyAgentActivity(
        sessionID: UUID,
        title: String,
        summary: String?,
        activityType: String,
        activityDescription: String?
    ) {
        let description = activityDescription ?? title
        let isAgenticActivity = isAgenticActivityPayload(
            title: title,
            summary: summary,
            activityType: activityType
        )
        switch activityType {
        case "active":
            if isAgenticActivity {
                sessionService.setAgentActivity(for: sessionID, activity: .active(description: description))
            }
        case "waiting":
            if isAgenticActivity {
                sessionService.setAgentActivity(for: sessionID, activity: .waiting(description: description))
            }
        case "completed":
            if isAgenticActivity {
                sessionService.setAgentActivity(for: sessionID, activity: .completed(description: description))
            }
        case "error":
            if isAgenticActivity {
                sessionService.setAgentActivity(for: sessionID, activity: .error(description: description))
            }
        case "clear":
            sessionService.setAgentActivity(for: sessionID, activity: nil)
        default:
            break
        }
    }

    private func parseBool(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.lowercased() {
        case "1", "true", "yes", "y":
            return true
        default:
            return false
        }
    }

    private func parseList(_ value: String?) -> [String] {
        guard let value else { return [] }
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func resolveSessionID(_ query: String) -> UUID? {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if let exactID = UUID(uuidString: cleaned),
           sessionService.sessions.contains(where: { $0.id == exactID }) {
            return exactID
        }
        let matches = sessionService.sessions.filter { session in
            session.title.caseInsensitiveCompare(cleaned) == .orderedSame
                || session.title.localizedCaseInsensitiveContains(cleaned)
        }
        guard matches.count == 1 else { return nil }
        return matches[0].id
    }

    private func isAgenticActivityPayload(title: String, summary: String?, activityType: String) -> Bool {
        if activityType == "clear" {
            return true
        }

        let haystack = [title, summary ?? ""]
            .joined(separator: " ")
            .lowercased()
        guard !haystack.isEmpty else { return false }

        let trackedPrefixes = ["claude", "aider", "cursor", "codex", "copilot", "cody", "goose"]
        return trackedPrefixes.contains { command in
            haystack.contains("\(command) started")
                || haystack.contains("\(command) finished")
                || haystack.contains("\(command) failed")
                || haystack.contains("running: \(command)")
        }
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "{}"
    }
}
