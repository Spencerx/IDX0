import Foundation

enum WorkflowStoreError: LocalizedError {
    case unsupportedSchemaVersion(Int, file: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version, let file):
            return "Unsupported schema version \(version) in \(file)"
        }
    }
}

private func workflowCodecs() -> (encoder: JSONEncoder, decoder: JSONDecoder) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    return (encoder, decoder)
}

private func workflowAtomicWrite(data: Data, to destination: URL, fileManager: FileManager) throws {
    try fileManager.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: destination, options: .atomic)
}

private func workflowTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
}

private func workflowMoveCorruptFileAside(url: URL, fileLabel: String, fileManager: FileManager) throws {
    guard fileManager.fileExists(atPath: url.path) else { return }
    let backupURL = url.deletingLastPathComponent()
        .appendingPathComponent("\(fileLabel).corrupt.\(workflowTimestamp()).json")
    try fileManager.moveItem(at: url, to: backupURL)
}

private func workflowLoad<T: Codable>(
    url: URL,
    fileLabel: String,
    fileManager: FileManager,
    defaultPayload: T,
    schemaVersion: ((T) -> Int?)
) throws -> T {
    guard fileManager.fileExists(atPath: url.path) else {
        return defaultPayload
    }

    do {
        let data = try Data(contentsOf: url)
        let decoded = try workflowCodecs().decoder.decode(T.self, from: data)
        if let parsedSchema = schemaVersion(decoded), parsedSchema > PersistenceSchema.currentVersion {
            throw WorkflowStoreError.unsupportedSchemaVersion(parsedSchema, file: fileLabel)
        }
        return decoded
    } catch let error as WorkflowStoreError {
        throw error
    } catch {
        try workflowMoveCorruptFileAside(url: url, fileLabel: fileLabel, fileManager: fileManager)
        Logger.error("Failed loading \(fileLabel): \(error.localizedDescription)")
        return defaultPayload
    }
}

private func workflowSave<T: Codable>(
    payload: T,
    url: URL,
    fileManager: FileManager
) throws {
    let data = try workflowCodecs().encoder.encode(payload)
    try workflowAtomicWrite(data: data, to: url, fileManager: fileManager)
}

struct QueueStore {
    private let url: URL
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func load() throws -> QueueFilePayload {
        let payload = try workflowLoad(
            url: url,
            fileLabel: "queue",
            fileManager: fileManager,
            defaultPayload: QueueFilePayload(),
            schemaVersion: { $0.schemaVersion }
        )
        return QueueFilePayload(schemaVersion: PersistenceSchema.currentVersion, items: payload.items)
    }

    func save(_ payload: QueueFilePayload) throws {
        try workflowSave(payload: payload, url: url, fileManager: fileManager)
    }
}

struct TimelineStore {
    private let url: URL
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func load() throws -> TimelineFilePayload {
        let payload = try workflowLoad(
            url: url,
            fileLabel: "timeline",
            fileManager: fileManager,
            defaultPayload: TimelineFilePayload(),
            schemaVersion: { $0.schemaVersion }
        )
        return TimelineFilePayload(schemaVersion: PersistenceSchema.currentVersion, items: payload.items)
    }

    func save(_ payload: TimelineFilePayload) throws {
        try workflowSave(payload: payload, url: url, fileManager: fileManager)
    }
}

struct CheckpointStore {
    private let url: URL
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func load() throws -> CheckpointFilePayload {
        let payload = try workflowLoad(
            url: url,
            fileLabel: "checkpoints",
            fileManager: fileManager,
            defaultPayload: CheckpointFilePayload(),
            schemaVersion: { $0.schemaVersion }
        )
        return CheckpointFilePayload(schemaVersion: PersistenceSchema.currentVersion, checkpoints: payload.checkpoints)
    }

    func save(_ payload: CheckpointFilePayload) throws {
        try workflowSave(payload: payload, url: url, fileManager: fileManager)
    }
}

struct HandoffStore {
    private let url: URL
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func load() throws -> HandoffFilePayload {
        let payload = try workflowLoad(
            url: url,
            fileLabel: "handoffs",
            fileManager: fileManager,
            defaultPayload: HandoffFilePayload(),
            schemaVersion: { $0.schemaVersion }
        )
        return HandoffFilePayload(schemaVersion: PersistenceSchema.currentVersion, handoffs: payload.handoffs)
    }

    func save(_ payload: HandoffFilePayload) throws {
        try workflowSave(payload: payload, url: url, fileManager: fileManager)
    }
}

struct ReviewStore {
    private let url: URL
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func load() throws -> ReviewFilePayload {
        let payload = try workflowLoad(
            url: url,
            fileLabel: "reviews",
            fileManager: fileManager,
            defaultPayload: ReviewFilePayload(),
            schemaVersion: { $0.schemaVersion }
        )
        return ReviewFilePayload(schemaVersion: PersistenceSchema.currentVersion, reviews: payload.reviews)
    }

    func save(_ payload: ReviewFilePayload) throws {
        try workflowSave(payload: payload, url: url, fileManager: fileManager)
    }
}

struct ApprovalStore {
    private let url: URL
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func load() throws -> ApprovalFilePayload {
        let payload = try workflowLoad(
            url: url,
            fileLabel: "approvals",
            fileManager: fileManager,
            defaultPayload: ApprovalFilePayload(),
            schemaVersion: { $0.schemaVersion }
        )
        return ApprovalFilePayload(schemaVersion: PersistenceSchema.currentVersion, approvals: payload.approvals)
    }

    func save(_ payload: ApprovalFilePayload) throws {
        try workflowSave(payload: payload, url: url, fileManager: fileManager)
    }
}

struct LayoutStore {
    private let url: URL
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func load() throws -> LayoutFilePayload {
        let payload = try workflowLoad(
            url: url,
            fileLabel: "layout",
            fileManager: fileManager,
            defaultPayload: LayoutFilePayload(),
            schemaVersion: { $0.schemaVersion }
        )
        return LayoutFilePayload(schemaVersion: PersistenceSchema.currentVersion, layoutState: payload.layoutState)
    }

    func save(_ payload: LayoutFilePayload) throws {
        try workflowSave(payload: payload, url: url, fileManager: fileManager)
    }
}

struct AgentEventStore {
    private let url: URL
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func load() throws -> AgentEventFilePayload {
        let payload = try workflowLoad(
            url: url,
            fileLabel: "agent-events",
            fileManager: fileManager,
            defaultPayload: AgentEventFilePayload(),
            schemaVersion: { $0.schemaVersion }
        )
        return AgentEventFilePayload(schemaVersion: PersistenceSchema.currentVersion, handledEventIDs: payload.handledEventIDs)
    }

    func save(_ payload: AgentEventFilePayload) throws {
        try workflowSave(payload: payload, url: url, fileManager: fileManager)
    }
}
