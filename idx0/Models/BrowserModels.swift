import Foundation

struct BrowserBookmark: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var url: String
    var createdAt: Date

    init(id: UUID = UUID(), title: String, url: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.createdAt = createdAt
    }
}

struct BrowserHistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var url: String
    var visitedAt: Date

    init(id: UUID = UUID(), title: String, url: String, visitedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.visitedAt = visitedAt
    }
}
