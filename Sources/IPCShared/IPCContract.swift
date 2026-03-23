import Foundation

public enum IPCCommand {
    public static let open = "open"
    public static let newSession = "newSession"
    public static let newSessionWithTool = "newSessionWithTool"
    public static let focusSession = "focusSession"
    public static let listSessions = "listSessions"
    public static let createCheckpoint = "createCheckpoint"
    public static let createHandoff = "createHandoff"
    public static let requestReview = "requestReview"
    public static let listQueue = "listQueue"
    public static let listApprovals = "listApprovals"
    public static let respondApproval = "respondApproval"
    public static let listVibeTools = "listVibeTools"
    public static let agentEvent = "agentEvent"
    public static let setReviewStatus = "setReviewStatus"
    public static let markQueueResolved = "markQueueResolved"
    public static let notify = "notify"

    public static let all: [String] = [
        open,
        newSession,
        newSessionWithTool,
        focusSession,
        listSessions,
        createCheckpoint,
        createHandoff,
        requestReview,
        listQueue,
        listApprovals,
        respondApproval,
        listVibeTools,
        agentEvent,
        setReviewStatus,
        markQueueResolved,
        notify
    ]
}

public struct IPCRequest: Codable, Sendable {
    public let command: String
    public let payload: [String: String]

    public init(command: String, payload: [String: String]) {
        self.command = command
        self.payload = payload
    }
}

public struct IPCResponse: Codable, Sendable {
    public let success: Bool
    public let message: String?
    public let data: [String: String]?

    public init(success: Bool, message: String?, data: [String: String]?) {
        self.success = success
        self.message = message
        self.data = data
    }
}
