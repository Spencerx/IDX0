import Foundation
import XCTest
@testable import idx0

@MainActor
final class AutoCheckpointServiceTests: XCTestCase {
    func testCreateCheckpointPrunesAndPersists() async throws {
        let sessionID = UUID()
        let tempDirectory = makeTempDirectory(prefix: "auto-checkpoint-prune")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageURL = tempDirectory.appendingPathComponent("checkpoints.json")
        let git = StubGitService(
            currentCommit: "abc123",
            currentBranchName: "main",
            porcelainStatus: "",
            diffStatValue: DiffStat(filesChanged: 1, additions: 10, deletions: 2)
        )

        let service = AutoCheckpointService(gitService: git, storageURL: storageURL)
        for _ in 0..<(AutoCheckpointService.maxCheckpointsPerSession + 2) {
            await service.createCheckpoint(sessionID: sessionID, repoPath: tempDirectory.path)
        }

        XCTAssertEqual(service.checkpointsForSession(sessionID).count, AutoCheckpointService.maxCheckpointsPerSession)
        XCTAssertNotNil(service.latestCheckpoint(for: sessionID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))

        let reloaded = AutoCheckpointService(gitService: git, storageURL: storageURL)
        XCTAssertEqual(reloaded.checkpointsForSession(sessionID).count, AutoCheckpointService.maxCheckpointsPerSession)

        reloaded.removeCheckpoints(for: sessionID)
        XCTAssertTrue(reloaded.checkpointsForSession(sessionID).isEmpty)
    }

    func testCreateCheckpointSkipsWhenCommitIsUnavailable() async {
        let sessionID = UUID()
        let tempDirectory = makeTempDirectory(prefix: "auto-checkpoint-empty")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let service = AutoCheckpointService(
            gitService: StubGitService(
                currentCommit: nil,
                currentBranchName: nil,
                porcelainStatus: "",
                diffStatValue: nil
            ),
            storageURL: tempDirectory.appendingPathComponent("checkpoints.json")
        )

        await service.createCheckpoint(sessionID: sessionID, repoPath: tempDirectory.path)
        XCTAssertTrue(service.checkpointsForSession(sessionID).isEmpty)
    }

    func testRestoreCheckpointResetsRepositoryToCommit() async throws {
        let tempDirectory = makeTempDirectory(prefix: "auto-checkpoint-restore")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let repoDirectory = tempDirectory.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDirectory, withIntermediateDirectories: true)
        try runGit(["init"], in: repoDirectory)
        try runGit(["config", "user.email", "idx0-tests@example.com"], in: repoDirectory)
        try runGit(["config", "user.name", "idx0 Tests"], in: repoDirectory)

        let fileURL = repoDirectory.appendingPathComponent("README.md")
        try "one\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: repoDirectory)
        try runGit(["commit", "-m", "first"], in: repoDirectory)
        let firstCommit = try runGit(["rev-parse", "HEAD"], in: repoDirectory)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        try "two\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: repoDirectory)
        try runGit(["commit", "-m", "second"], in: repoDirectory)

        let service = AutoCheckpointService(
            gitService: StubGitService(currentCommit: nil, currentBranchName: nil, porcelainStatus: "", diffStatValue: nil),
            storageURL: tempDirectory.appendingPathComponent("checkpoints.json")
        )
        let checkpoint = AutoCheckpointService.Checkpoint(
            id: UUID(),
            sessionID: UUID(),
            repoPath: repoDirectory.path,
            commitSHA: firstCommit,
            stashRef: nil,
            branchName: nil,
            createdAt: Date(),
            diffStat: nil
        )

        try await service.restoreCheckpoint(checkpoint)
        let headAfterRestore = try runGit(["rev-parse", "HEAD"], in: repoDirectory)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(headAfterRestore, firstCommit)
    }

    func testRestoreCheckpointThrowsOnFailure() async {
        let tempDirectory = makeTempDirectory(prefix: "auto-checkpoint-restore-fail")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let service = AutoCheckpointService(
            gitService: StubGitService(currentCommit: nil, currentBranchName: nil, porcelainStatus: "", diffStatValue: nil),
            storageURL: tempDirectory.appendingPathComponent("checkpoints.json")
        )
        let checkpoint = AutoCheckpointService.Checkpoint(
            id: UUID(),
            sessionID: UUID(),
            repoPath: tempDirectory.path,
            commitSHA: "deadbeef",
            stashRef: nil,
            branchName: nil,
            createdAt: Date(),
            diffStat: nil
        )

        do {
            try await service.restoreCheckpoint(checkpoint)
            XCTFail("Expected restore failure")
        } catch let error as AutoCheckpointService.CheckpointError {
            guard case .restoreFailed(let message) = error else {
                XCTFail("Unexpected checkpoint error: \(error)")
                return
            }
            XCTAssertFalse(message.isEmpty)
            XCTAssertTrue(error.localizedDescription.contains("Failed to restore checkpoint"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    private func makeTempDirectory(prefix: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "AutoCheckpointServiceTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: stderr]
            )
        }

        return stdout
    }
}

private struct StubGitService: GitServiceProtocol {
    let currentCommit: String?
    let currentBranchName: String?
    let porcelainStatus: String
    let diffStatValue: DiffStat?

    func repoInfo(for path: String) async throws -> GitRepoInfo {
        GitRepoInfo(topLevelPath: path, currentBranch: currentBranchName, repoName: "repo")
    }

    func currentBranch(repoPath: String) async throws -> String? {
        currentBranchName
    }

    func currentCommitSHA(repoPath: String) async throws -> String? {
        currentCommit
    }

    func localBranches(repoPath: String) async throws -> [String] { [] }

    func listWorktrees(repoPath: String) async throws -> [WorktreeInfo] { [] }

    func createWorktree(repoPath: String, branchName: String, worktreePath: String) async throws -> WorktreeInfo {
        WorktreeInfo(repoPath: repoPath, worktreePath: worktreePath, branchName: branchName)
    }

    func statusPorcelain(path: String) async throws -> String {
        porcelainStatus
    }

    func removeWorktree(repoPath: String, worktreePath: String) async throws {}

    func diffNameStatus(path: String) async throws -> [ChangedFileSummary] { [] }

    func diffNameStatus(path: String, between leftRef: String, and rightRef: String) async throws -> [ChangedFileSummary] { [] }

    func diffStat(path: String) async throws -> DiffStat? {
        diffStatValue
    }

    func diffStat(path: String, between leftRef: String, and rightRef: String) async throws -> DiffStat? {
        diffStatValue
    }
}
