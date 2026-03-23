import Foundation

struct ChangedFileSummary: Codable, Equatable {
    let path: String
    let additions: Int?
    let deletions: Int?
    let status: String
}

struct DiffStat: Codable, Equatable {
    let filesChanged: Int
    let additions: Int
    let deletions: Int
}

enum TestStatus: String, Codable {
    case passed
    case failed
    case unknown
}

struct TestSummary: Codable, Equatable {
    let status: TestStatus
    let summaryText: String
}

enum CheckpointSource: String, Codable {
    case manual
    case agentEvent
    case autoCommit
}

struct Checkpoint: Identifiable, Codable, Equatable {
    let id: UUID
    let sessionID: UUID
    let repoPath: String?
    let branchName: String?
    let worktreePath: String?
    let title: String
    let summary: String
    let commitSHA: String?
    let changedFiles: [ChangedFileSummary]
    let diffStat: DiffStat?
    let testSummary: TestSummary?
    let createdAt: Date
    let source: CheckpointSource
}

enum HandoffStatus: String, Codable {
    case pending
    case accepted
    case resolved
}

struct Handoff: Identifiable, Codable, Equatable {
    let id: UUID
    let sourceSessionID: UUID
    let targetSessionID: UUID?
    let checkpointID: UUID?
    let title: String
    let summary: String
    let risks: [String]
    let nextActions: [String]
    let createdAt: Date
    var status: HandoffStatus
}

enum ReviewStatus: String, Codable {
    case open
    case approved
    case changesRequested
    case deferred
}

struct ReviewRequest: Identifiable, Codable, Equatable {
    let id: UUID
    let sourceSessionID: UUID
    let checkpointID: UUID?
    let createdAt: Date
    let summary: String
    let changedFiles: [ChangedFileSummary]
    let diffStat: DiffStat?
    let testSummary: TestSummary?
    var status: ReviewStatus
}

enum ApprovalStatus: String, Codable {
    case pending
    case approved
    case denied
    case deferred
}

struct ApprovalRequest: Identifiable, Codable, Equatable {
    let id: UUID
    let sessionID: UUID
    let createdAt: Date
    let title: String
    let summary: String
    let requestedAction: String
    let scopeDescription: String?
    var status: ApprovalStatus
}

enum QueueItemCategory: String, Codable, CaseIterable {
    case approvalNeeded
    case reviewRequested
    case blocked
    case completed
    case error
    case informational

    var urgencyRank: Int {
        switch self {
        case .approvalNeeded:
            return 0
        case .reviewRequested:
            return 1
        case .error:
            return 2
        case .blocked:
            return 3
        case .completed:
            return 4
        case .informational:
            return 5
        }
    }

    var displayLabel: String {
        switch self {
        case .approvalNeeded:
            return "Approval Needed"
        case .reviewRequested:
            return "Review Requested"
        case .blocked:
            return "Blocked"
        case .completed:
            return "Completed"
        case .error:
            return "Error"
        case .informational:
            return "Info"
        }
    }
}

struct SupervisionQueueItem: Identifiable, Codable, Equatable {
    let id: UUID
    let sessionID: UUID
    let relatedObjectID: UUID?
    let category: QueueItemCategory
    let title: String
    let subtitle: String?
    let createdAt: Date
    var isResolved: Bool
    var isPinned: Bool
}

enum TimelineItemType: String, Codable {
    case sessionCreated
    case sessionClosed
    case sessionLaunched
    case checkpointCreated
    case handoffCreated
    case handoffUpdated
    case reviewRequested
    case reviewUpdated
    case approvalRequested
    case approvalUpdated
    case statusProgress
    case statusCompleted
    case statusError
    case statusBlocked
    case statusNeedsInput
}

struct TimelineItem: Identifiable, Codable, Equatable {
    let id: UUID
    let sessionID: UUID
    let createdAt: Date
    let type: TimelineItemType
    let title: String
    let relatedObjectID: UUID?
}

struct QueueFilePayload: Codable {
    var schemaVersion: Int
    var items: [SupervisionQueueItem]

    init(schemaVersion: Int = PersistenceSchema.currentVersion, items: [SupervisionQueueItem] = []) {
        self.schemaVersion = schemaVersion
        self.items = items
    }
}

struct TimelineFilePayload: Codable {
    var schemaVersion: Int
    var items: [TimelineItem]

    init(schemaVersion: Int = PersistenceSchema.currentVersion, items: [TimelineItem] = []) {
        self.schemaVersion = schemaVersion
        self.items = items
    }
}

struct CheckpointFilePayload: Codable {
    var schemaVersion: Int
    var checkpoints: [Checkpoint]

    init(schemaVersion: Int = PersistenceSchema.currentVersion, checkpoints: [Checkpoint] = []) {
        self.schemaVersion = schemaVersion
        self.checkpoints = checkpoints
    }
}

struct HandoffFilePayload: Codable {
    var schemaVersion: Int
    var handoffs: [Handoff]

    init(schemaVersion: Int = PersistenceSchema.currentVersion, handoffs: [Handoff] = []) {
        self.schemaVersion = schemaVersion
        self.handoffs = handoffs
    }
}

struct ReviewFilePayload: Codable {
    var schemaVersion: Int
    var reviews: [ReviewRequest]

    init(schemaVersion: Int = PersistenceSchema.currentVersion, reviews: [ReviewRequest] = []) {
        self.schemaVersion = schemaVersion
        self.reviews = reviews
    }
}

struct ApprovalFilePayload: Codable {
    var schemaVersion: Int
    var approvals: [ApprovalRequest]

    init(schemaVersion: Int = PersistenceSchema.currentVersion, approvals: [ApprovalRequest] = []) {
        self.schemaVersion = schemaVersion
        self.approvals = approvals
    }
}

enum AgentEventType: String, Codable {
    case progress
    case checkpoint
    case handoff
    case reviewRequest
    case approvalRequest
    case completed
    case blocked
    case error
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
            return
        }
        throw DecodingError.typeMismatch(
            JSONValue.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case .number(let value) = self { return Int(value) }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
}

struct SessionUsage: Codable, Equatable {
    var totalInputTokens: Int = 0
    var totalOutputTokens: Int = 0
    var totalEstimatedCostUSD: Double = 0
    var eventCount: Int = 0
}

struct AgentEventEnvelope: Codable {
    let schemaVersion: Int
    let eventID: UUID
    let sessionID: UUID?
    let sessionTitleHint: String?
    let timestamp: Date
    let eventType: AgentEventType
    let payload: JSONValue
}

struct AgentEventFilePayload: Codable {
    var schemaVersion: Int
    var handledEventIDs: [UUID]

    init(schemaVersion: Int = PersistenceSchema.currentVersion, handledEventIDs: [UUID] = []) {
        self.schemaVersion = schemaVersion
        self.handledEventIDs = handledEventIDs
    }
}
