import Foundation

enum SessionStoreError: LocalizedError {
    case unsupportedSchemaVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported sessions schema version: \(version)"
        }
    }
}

struct SessionStore {
    private let url: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
        let codecs = makeJSONCodecs()
        self.encoder = codecs.encoder
        self.decoder = codecs.decoder
    }

    func load() throws -> SessionsFilePayload {
        guard fileManager.fileExists(atPath: url.path) else {
            return SessionsFilePayload()
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try decoder.decode(SessionsFilePayload.self, from: data)
            guard decoded.schemaVersion >= 1,
                  decoded.schemaVersion <= PersistenceSchema.currentVersion else {
                throw SessionStoreError.unsupportedSchemaVersion(decoded.schemaVersion)
            }

            return SessionsFilePayload(
                schemaVersion: PersistenceSchema.currentVersion,
                selectedSessionID: decoded.selectedSessionID,
                sessions: decoded.sessions
            )
        } catch let error as SessionStoreError {
            throw error
        } catch {
            try moveCorruptFileAside()
            Logger.error("Failed loading sessions file: \(error.localizedDescription)")
            return SessionsFilePayload()
        }
    }

    func save(payload: SessionsFilePayload) throws {
        let data = try encoder.encode(payload)
        try atomicWrite(data: data, to: url, fileManager: fileManager)
    }

    private func moveCorruptFileAside() throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("sessions.corrupt.\(timestamp()).json")
        try fileManager.moveItem(at: url, to: backupURL)
    }
}

enum ProjectStoreError: LocalizedError {
    case unsupportedSchemaVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported projects schema version: \(version)"
        }
    }
}

struct ProjectStore {
    private let url: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
        let codecs = makeJSONCodecs()
        self.encoder = codecs.encoder
        self.decoder = codecs.decoder
    }

    func load() throws -> ProjectsFilePayload {
        guard fileManager.fileExists(atPath: url.path) else {
            return ProjectsFilePayload()
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try decoder.decode(ProjectsFilePayload.self, from: data)
            guard decoded.schemaVersion <= PersistenceSchema.currentVersion else {
                throw ProjectStoreError.unsupportedSchemaVersion(decoded.schemaVersion)
            }
            return ProjectsFilePayload(groups: decoded.groups)
        } catch let error as ProjectStoreError {
            throw error
        } catch {
            try moveCorruptFileAside()
            Logger.error("Failed loading projects file: \(error.localizedDescription)")
            return ProjectsFilePayload()
        }
    }

    func save(payload: ProjectsFilePayload) throws {
        let data = try encoder.encode(payload)
        try atomicWrite(data: data, to: url, fileManager: fileManager)
    }

    private func moveCorruptFileAside() throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("projects.corrupt.\(timestamp()).json")
        try fileManager.moveItem(at: url, to: backupURL)
    }
}

enum InboxStoreError: LocalizedError {
    case unsupportedSchemaVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported inbox schema version: \(version)"
        }
    }
}

struct InboxStore {
    private let url: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
        let codecs = makeJSONCodecs()
        self.encoder = codecs.encoder
        self.decoder = codecs.decoder
    }

    func load() throws -> InboxFilePayload {
        guard fileManager.fileExists(atPath: url.path) else {
            return InboxFilePayload()
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try decoder.decode(InboxFilePayload.self, from: data)
            guard decoded.schemaVersion <= PersistenceSchema.currentVersion else {
                throw InboxStoreError.unsupportedSchemaVersion(decoded.schemaVersion)
            }
            return InboxFilePayload(items: decoded.items)
        } catch let error as InboxStoreError {
            throw error
        } catch {
            try moveCorruptFileAside()
            Logger.error("Failed loading inbox file: \(error.localizedDescription)")
            return InboxFilePayload()
        }
    }

    func save(payload: InboxFilePayload) throws {
        let data = try encoder.encode(payload)
        try atomicWrite(data: data, to: url, fileManager: fileManager)
    }

    private func moveCorruptFileAside() throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("inbox.corrupt.\(timestamp()).json")
        try fileManager.moveItem(at: url, to: backupURL)
    }
}

private func makeJSONCodecs() -> (encoder: JSONEncoder, decoder: JSONDecoder) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    return (encoder, decoder)
}

private func atomicWrite(data: Data, to destination: URL, fileManager: FileManager) throws {
    try fileManager.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: destination, options: .atomic)
}

private func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
}
