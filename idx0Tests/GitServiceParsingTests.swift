import Foundation
import XCTest
@testable import idx0

final class GitServiceParsingTests: XCTestCase {
    func testGitServiceErrorDescriptionsAreUserFriendly() {
        XCTAssertEqual(GitServiceError.invalidPath("/tmp/missing").errorDescription, "The path does not exist: /tmp/missing")
        XCTAssertEqual(GitServiceError.notGitRepository("/tmp/repo").errorDescription, "This folder is not a Git repository. Choose another folder or turn off worktree creation.")
        XCTAssertEqual(GitServiceError.commandFailed("boom").errorDescription, "boom")
        XCTAssertEqual(GitServiceError.branchAlreadyExists.errorDescription, "Branch already exists. Choose a different branch name or attach an existing worktree.")
    }

    func testDiffNameStatusMergesNumstatCounts() async throws {
        let repo = "/tmp/repo"
        let runner = StubRunner(
            results: [
                "/usr/bin/git -C \(repo) diff --name-status": ProcessResult(
                    exitCode: 0,
                    stdout: "M\tSources/App.swift\nA\tREADME.md",
                    stderr: ""
                ),
                "/usr/bin/git -C \(repo) diff --numstat": ProcessResult(
                    exitCode: 0,
                    stdout: "10\t2\tSources/App.swift\n5\t0\tREADME.md",
                    stderr: ""
                )
            ]
        )
        let service = GitService(runner: runner)

        let files = try await service.diffNameStatus(path: repo)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0], ChangedFileSummary(path: "Sources/App.swift", additions: 10, deletions: 2, status: "M"))
        XCTAssertEqual(files[1], ChangedFileSummary(path: "README.md", additions: 5, deletions: 0, status: "A"))
    }

    func testDiffStatParsesShortstatSummary() async throws {
        let repo = "/tmp/repo"
        let runner = StubRunner(
            results: [
                "/usr/bin/git -C \(repo) diff --shortstat": ProcessResult(
                    exitCode: 0,
                    stdout: " 2 files changed, 15 insertions(+), 3 deletions(-)",
                    stderr: ""
                )
            ]
        )
        let service = GitService(runner: runner)

        let stat = try await service.diffStat(path: repo)
        XCTAssertEqual(stat, DiffStat(filesChanged: 2, additions: 15, deletions: 3))
    }

    func testCurrentCommitSHAFailureSurfacesCommandError() async {
        let repo = "/tmp/repo"
        let runner = StubRunner(
            results: [
                "/usr/bin/git -C \(repo) rev-parse HEAD": ProcessResult(
                    exitCode: 1,
                    stdout: "",
                    stderr: "fatal: bad revision"
                )
            ]
        )
        let service = GitService(runner: runner)

        do {
            _ = try await service.currentCommitSHA(repoPath: repo)
            XCTFail("Expected command failure")
        } catch let error as GitServiceError {
            guard case .commandFailed(let message) = error else {
                XCTFail("Unexpected GitServiceError: \(error)")
                return
            }
            XCTAssertTrue(message.contains("fatal"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLocalBranchesAreSortedAndTrimmed() async throws {
        let repo = "/tmp/repo"
        let runner = StubRunner(
            results: [
                "/usr/bin/git -C \(repo) branch --format=%(refname:short)": ProcessResult(
                    exitCode: 0,
                    stdout: "zeta\n\nAlpha\nbeta\n",
                    stderr: ""
                )
            ]
        )
        let service = GitService(runner: runner)

        let branches = try await service.localBranches(repoPath: repo)
        XCTAssertEqual(branches, ["Alpha", "beta", "zeta"])
    }

    func testCreateWorktreeMapsExistingBranchToBranchAlreadyExists() async {
        let repo = "/tmp/repo"
        let worktreePath = "/tmp/repo-worktree"
        let runner = StubRunner(
            results: [
                "/usr/bin/git -C \(repo) worktree add \(worktreePath) -b feature/test": ProcessResult(
                    exitCode: 1,
                    stdout: "",
                    stderr: "fatal: a branch named 'feature/test' already exists"
                )
            ]
        )
        let service = GitService(runner: runner)

        do {
            _ = try await service.createWorktree(repoPath: repo, branchName: "feature/test", worktreePath: worktreePath)
            XCTFail("Expected branchAlreadyExists")
        } catch let error as GitServiceError {
            guard case .branchAlreadyExists = error else {
                XCTFail("Expected branchAlreadyExists, got \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStatusRemoveAndFullDiffCommands() async throws {
        let repo = "/tmp/repo"
        let worktreePath = "/tmp/repo-worktree"
        let runner = StubRunner(
            results: [
                "/usr/bin/git -C \(repo) status --porcelain": ProcessResult(exitCode: 0, stdout: " M Sources/App.swift", stderr: ""),
                "/usr/bin/git -C \(repo) worktree remove \(worktreePath)": ProcessResult(exitCode: 0, stdout: "", stderr: ""),
                "/usr/bin/git -C \(repo) diff": ProcessResult(exitCode: 0, stdout: "diff --git a/a b/a", stderr: "")
            ]
        )
        let service = GitService(runner: runner)

        let status = try await service.statusPorcelain(path: repo)
        XCTAssertEqual(status, " M Sources/App.swift")

        try await service.removeWorktree(repoPath: repo, worktreePath: worktreePath)

        let diff = try await service.fullDiff(path: repo)
        XCTAssertTrue(diff.contains("diff --git"))
    }

    func testFullDiffSinceCombinesCommittedAndUncommittedDiffs() async throws {
        let repo = "/tmp/repo"
        let runner = StubRunner(
            results: [
                "/usr/bin/git -C \(repo) diff abc123...HEAD": ProcessResult(
                    exitCode: 0,
                    stdout: "committed",
                    stderr: ""
                ),
                "/usr/bin/git -C \(repo) diff": ProcessResult(
                    exitCode: 0,
                    stdout: "uncommitted",
                    stderr: ""
                )
            ]
        )
        let service = GitService(runner: runner)

        let diff = try await service.fullDiff(path: repo, since: "abc123")
        XCTAssertEqual(diff, "committed\nuncommitted")
    }

    private struct StubRunner: ProcessRunnerProtocol {
        let results: [String: ProcessResult]

        func run(executable: String, arguments: [String], currentDirectory: String?) async throws -> ProcessResult {
            let key = ([executable] + arguments).joined(separator: " ")
            if let result = results[key] {
                return result
            }
            throw NSError(domain: "GitServiceParsingTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing stub for \(key)"])
        }
    }
}
