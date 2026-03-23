import Foundation

@MainActor
final class BrowserDataStore: ObservableObject {
    static let shared = BrowserDataStore()

    @Published private(set) var bookmarks: [BrowserBookmark] = []
    @Published private(set) var history: [BrowserHistoryEntry] = []

    private let fileManager: FileManager
    private let bookmarksURL: URL
    private let historyURL: URL
    private let maxHistoryEntries = 500

    private init(
        fileManager: FileManager = .default,
        appSupportDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        let appSupport = appSupportDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let browserDir = appSupport.appendingPathComponent("idx0/Browser", isDirectory: true)
        try? fileManager.createDirectory(at: browserDir, withIntermediateDirectories: true)
        bookmarksURL = browserDir.appendingPathComponent("bookmarks.json")
        historyURL = browserDir.appendingPathComponent("history.json")
        loadBookmarks()
        loadHistory()
    }

    init(
        bookmarksURL: URL,
        historyURL: URL,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.bookmarksURL = bookmarksURL
        self.historyURL = historyURL
        try? fileManager.createDirectory(at: bookmarksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        loadBookmarks()
        loadHistory()
    }

    // MARK: - Bookmarks

    func addBookmark(title: String, url: String) {
        guard !bookmarks.contains(where: { $0.url == url }) else { return }
        let bookmark = BrowserBookmark(title: title, url: url)
        bookmarks.append(bookmark)
        saveBookmarks()
    }

    func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        saveBookmarks()
    }

    func removeBookmark(url: String) {
        bookmarks.removeAll { $0.url == url }
        saveBookmarks()
    }

    func isBookmarked(url: String?) -> Bool {
        guard let url else { return false }
        return bookmarks.contains { $0.url == url }
    }

    // MARK: - History

    func recordVisit(title: String, url: String) {
        let entry = BrowserHistoryEntry(title: title, url: url)
        history.insert(entry, at: 0)
        if history.count > maxHistoryEntries {
            history = Array(history.prefix(maxHistoryEntries))
        }
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    func historySuggestions(for query: String) -> [BrowserHistoryEntry] {
        guard !query.isEmpty else { return [] }
        let lowered = query.lowercased()
        var seen = Set<String>()
        var results: [BrowserHistoryEntry] = []
        for entry in history {
            let urlMatch = entry.url.lowercased().contains(lowered)
            let titleMatch = entry.title.lowercased().contains(lowered)
            if (urlMatch || titleMatch) && !seen.contains(entry.url) {
                seen.insert(entry.url)
                results.append(entry)
            }
            if results.count >= 8 { break }
        }
        return results
    }

    func bookmarkSuggestions(for query: String) -> [BrowserBookmark] {
        guard !query.isEmpty else { return bookmarks }
        let lowered = query.lowercased()
        return bookmarks.filter {
            $0.url.lowercased().contains(lowered) || $0.title.lowercased().contains(lowered)
        }
    }

    // MARK: - Persistence

    private func loadBookmarks() {
        guard fileManager.fileExists(atPath: bookmarksURL.path) else { return }
        do {
            let data = try Data(contentsOf: bookmarksURL)
            bookmarks = try JSONDecoder().decode([BrowserBookmark].self, from: data)
        } catch {
            bookmarks = []
        }
    }

    private func saveBookmarks() {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            try data.write(to: bookmarksURL, options: .atomic)
        } catch {}
    }

    private func loadHistory() {
        guard fileManager.fileExists(atPath: historyURL.path) else { return }
        do {
            let data = try Data(contentsOf: historyURL)
            history = try JSONDecoder().decode([BrowserHistoryEntry].self, from: data)
        } catch {
            history = []
        }
    }

    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: historyURL, options: .atomic)
        } catch {}
    }
}
