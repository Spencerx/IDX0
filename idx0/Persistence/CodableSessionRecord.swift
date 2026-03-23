import Foundation

enum PersistenceSchema {
    static let currentVersion = 3
}

struct SessionsFilePayload: Codable {
    var schemaVersion: Int
    var selectedSessionID: UUID?
    var sessions: [Session]

    init(
        schemaVersion: Int = PersistenceSchema.currentVersion,
        selectedSessionID: UUID? = nil,
        sessions: [Session] = []
    ) {
        self.schemaVersion = schemaVersion
        self.selectedSessionID = selectedSessionID
        self.sessions = sessions
    }
}

struct ProjectsFilePayload: Codable {
    var schemaVersion: Int
    var groups: [ProjectGroup]

    init(schemaVersion: Int = PersistenceSchema.currentVersion, groups: [ProjectGroup] = []) {
        self.schemaVersion = schemaVersion
        self.groups = groups
    }
}

struct InboxFilePayload: Codable {
    var schemaVersion: Int
    var items: [AttentionItem]

    init(schemaVersion: Int = PersistenceSchema.currentVersion, items: [AttentionItem] = []) {
        self.schemaVersion = schemaVersion
        self.items = items
    }
}
