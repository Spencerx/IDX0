import Foundation
import XCTest
@testable import idx0

@MainActor
final class BrowserDataStoreTests: XCTestCase {
    func testBookmarksHistorySuggestionsAndPersistence() throws {
        let tempDirectory = makeTempDirectory(prefix: "browser-store")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let bookmarksURL = tempDirectory.appendingPathComponent("bookmarks.json")
        let historyURL = tempDirectory.appendingPathComponent("history.json")

        let store = BrowserDataStore(bookmarksURL: bookmarksURL, historyURL: historyURL)

        store.addBookmark(title: "Example", url: "https://example.com")
        store.addBookmark(title: "Duplicate", url: "https://example.com")
        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertTrue(store.isBookmarked(url: "https://example.com"))
        XCTAssertFalse(store.isBookmarked(url: nil))

        let bookmarkID = try XCTUnwrap(store.bookmarks.first?.id)
        store.removeBookmark(id: bookmarkID)
        XCTAssertFalse(store.isBookmarked(url: "https://example.com"))

        store.addBookmark(title: "idx0", url: "https://idx0.dev")
        store.removeBookmark(url: "https://idx0.dev")
        XCTAssertEqual(store.bookmarks.count, 0)

        for index in 0..<510 {
            let url = "https://example.com/page/\(index % 6)"
            store.recordVisit(title: "Page \(index)", url: url)
        }

        XCTAssertEqual(store.history.count, 500)

        let historySuggestions = store.historySuggestions(for: "example.com/page")
        XCTAssertLessThanOrEqual(historySuggestions.count, 8)
        XCTAssertEqual(Set(historySuggestions.map(\.url)).count, historySuggestions.count)

        store.addBookmark(title: "Docs", url: "https://docs.idx0.dev")
        store.addBookmark(title: "Site", url: "https://idx0.dev")
        XCTAssertEqual(store.bookmarkSuggestions(for: "").count, 2)
        XCTAssertEqual(store.bookmarkSuggestions(for: "docs").count, 1)

        let reloaded = BrowserDataStore(bookmarksURL: bookmarksURL, historyURL: historyURL)
        XCTAssertEqual(reloaded.bookmarks.count, 2)
        XCTAssertEqual(reloaded.history.count, 500)

        reloaded.clearHistory()
        XCTAssertEqual(reloaded.history.count, 0)
    }

    func testCorruptFilesLoadAsEmptyCollections() throws {
        let tempDirectory = makeTempDirectory(prefix: "browser-store-corrupt")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let bookmarksURL = tempDirectory.appendingPathComponent("bookmarks.json")
        let historyURL = tempDirectory.appendingPathComponent("history.json")
        try "not-json".write(to: bookmarksURL, atomically: true, encoding: .utf8)
        try "not-json".write(to: historyURL, atomically: true, encoding: .utf8)

        let store = BrowserDataStore(bookmarksURL: bookmarksURL, historyURL: historyURL)

        XCTAssertTrue(store.bookmarks.isEmpty)
        XCTAssertTrue(store.history.isEmpty)
    }

    private func makeTempDirectory(prefix: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
