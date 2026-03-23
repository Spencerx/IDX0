import Foundation
import XCTest
@testable import idx0

final class SessionStoreTests: XCTestCase {
    func testRoundTripPersistence() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("idx0-session-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = tempDir.appendingPathComponent("sessions.json")
        let store = SessionStore(url: url)

        let session = Session(
            id: UUID(),
            title: "Test",
            hasCustomTitle: true,
            createdAt: Date(timeIntervalSince1970: 1),
            lastActiveAt: Date(timeIntervalSince1970: 2),
            repoPath: "/tmp/repo",
            branchName: "main",
            worktreePath: nil,
            isWorktreeBacked: false,
            shellPath: "/bin/zsh",
            attentionState: .normal,
            statusText: nil,
            lastKnownCwd: "/tmp/repo"
        )

        try store.save(payload: SessionsFilePayload(schemaVersion: 1, selectedSessionID: session.id, sessions: [session]))
        let loaded = try store.load()

        XCTAssertEqual(loaded.sessions, [session])
        XCTAssertEqual(loaded.selectedSessionID, session.id)
        XCTAssertEqual(loaded.schemaVersion, PersistenceSchema.currentVersion)
    }

    func testCorruptFileIsMovedAside() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("idx0-session-store-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = tempDir.appendingPathComponent("sessions.json")
        try "not-json".data(using: .utf8)?.write(to: url)

        let store = SessionStore(url: url)
        let loaded = try store.load()
        XCTAssertTrue(loaded.sessions.isEmpty)

        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertTrue(files.contains(where: { $0.hasPrefix("sessions.corrupt.") }))
    }

    func testSchema2PayloadLoadsAndNormalizesToCurrentVersion() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("idx0-session-store-schema2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = tempDir.appendingPathComponent("sessions.json")
        let store = SessionStore(url: url)
        let session = Session(
            id: UUID(),
            title: "Schema2",
            hasCustomTitle: true,
            createdAt: Date(timeIntervalSince1970: 10),
            lastActiveAt: Date(timeIntervalSince1970: 11),
            repoPath: "/tmp/repo",
            branchName: "main",
            worktreePath: nil,
            isWorktreeBacked: false,
            shellPath: "/bin/zsh",
            attentionState: .normal,
            statusText: nil,
            lastKnownCwd: "/tmp/repo"
        )

        try store.save(payload: SessionsFilePayload(schemaVersion: 2, selectedSessionID: session.id, sessions: [session]))
        let loaded = try store.load()

        XCTAssertEqual(loaded.sessions, [session])
        XCTAssertEqual(loaded.selectedSessionID, session.id)
        XCTAssertEqual(loaded.schemaVersion, PersistenceSchema.currentVersion)
    }

    func testFutureSchemaThrowsUnsupportedSchemaVersion() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("idx0-session-store-future-schema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = tempDir.appendingPathComponent("sessions.json")
        let payload = SessionsFilePayload(schemaVersion: PersistenceSchema.currentVersion + 1, selectedSessionID: nil, sessions: [])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(payload).write(to: url)

        let store = SessionStore(url: url)
        XCTAssertThrowsError(try store.load()) { error in
            guard case SessionStoreError.unsupportedSchemaVersion = error else {
                XCTFail("Expected unsupported schema error, got \(error)")
                return
            }
        }
    }
}
