import Foundation
import XCTest
@testable import idx0

final class SessionModelTests: XCTestCase {
    func testAgentActivityDescriptionAndStateFlags() {
        let active = AgentActivity.active(description: "Working")
        let waiting = AgentActivity.waiting(description: "Needs input")

        XCTAssertEqual(active.description, "Working")
        XCTAssertTrue(active.isActive)
        XCTAssertFalse(active.isWaiting)

        XCTAssertEqual(waiting.description, "Needs input")
        XCTAssertFalse(waiting.isActive)
        XCTAssertTrue(waiting.isWaiting)
    }

    func testDisplayLabelsForSessionEnums() {
        XCTAssertEqual(SandboxProfile.fullAccess.displayLabel, "Full Access")
        XCTAssertEqual(SandboxProfile.worktreeWrite.displayLabel, "Worktree Write")
        XCTAssertEqual(SandboxProfile.worktreeAndTemp.displayLabel, "Worktree + Temp")

        XCTAssertEqual(NetworkPolicy.inherited.displayLabel, "Network On")
        XCTAssertEqual(NetworkPolicy.disabled.displayLabel, "Network Off")

        XCTAssertEqual(SandboxEnforcementState.unenforced.displayLabel, "Unenforced")
        XCTAssertEqual(SandboxEnforcementState.enforced.displayLabel, "Enforced")
        XCTAssertEqual(SandboxEnforcementState.degraded.displayLabel, "Degraded")
    }

    func testLaunchDirectoryPreferenceOrder() {
        let worktreeSession = makeSession(repoPath: "/tmp/repo", worktreePath: "/tmp/worktree", lastLaunchCwd: "/tmp/cwd")
        XCTAssertEqual(worktreeSession.launchDirectory, "/tmp/worktree")

        let repoSession = makeSession(repoPath: "/tmp/repo", worktreePath: nil, lastLaunchCwd: "/tmp/cwd")
        XCTAssertEqual(repoSession.launchDirectory, "/tmp/repo")

        let cwdSession = makeSession(repoPath: nil, worktreePath: nil, lastLaunchCwd: "/tmp/cwd")
        XCTAssertEqual(cwdSession.launchDirectory, "/tmp/cwd")

        let fallbackSession = makeSession(repoPath: nil, worktreePath: nil, lastLaunchCwd: "")
        XCTAssertEqual(fallbackSession.launchDirectory, FileManager.default.homeDirectoryForCurrentUser.path)
    }

    func testLaunchManifestUsesPersistedManifestWhenPresent() {
        let persistedManifest = SessionLaunchManifest(
            sessionID: UUID(),
            cwd: "/persisted",
            shellPath: "/bin/zsh",
            repoPath: "/tmp/repo",
            worktreePath: nil,
            sandboxProfile: .worktreeWrite,
            networkPolicy: .disabled,
            tempRoot: "/tmp",
            environment: ["KEY": "VALUE"],
            projectID: UUID().uuidString,
            ipcSocketPath: "/tmp/socket",
            directLaunchToolPath: "/usr/local/bin/codex"
        )

        let session = makeSession(
            repoPath: "/tmp/repo",
            worktreePath: nil,
            lastLaunchCwd: "/tmp/repo",
            lastLaunchManifest: persistedManifest
        )

        XCTAssertEqual(session.launchManifest, persistedManifest)
    }

    func testLaunchManifestFallsBackToDerivedValues() {
        let session = makeSession(
            repoPath: "/tmp/repo",
            worktreePath: nil,
            lastLaunchCwd: "/tmp/repo",
            lastLaunchManifest: nil
        )

        let manifest = session.launchManifest
        XCTAssertEqual(manifest.cwd, "/tmp/repo")
        XCTAssertEqual(manifest.repoPath, "/tmp/repo")
        XCTAssertEqual(manifest.worktreePath, nil)
        XCTAssertEqual(manifest.projectID, session.projectID?.uuidString)
    }

    func testSubtitlePrefersRepoThenKnownCwdThenLaunchCwd() {
        let repoSession = makeSession(repoPath: "/Users/me/project", worktreePath: nil, lastLaunchCwd: "/tmp/ignored")
        XCTAssertEqual(repoSession.subtitle, "project")

        let cwdSession = makeSession(repoPath: nil, worktreePath: nil, lastLaunchCwd: "/tmp/fallback", lastKnownCwd: "/Users/me/current")
        XCTAssertEqual(cwdSession.subtitle, "current")

        let launchSession = makeSession(repoPath: nil, worktreePath: nil, lastLaunchCwd: "/Users/me/launch", lastKnownCwd: nil)
        XCTAssertEqual(launchSession.subtitle, "launch")
    }

    func testSessionSurfaceFocusDecodesLegacyAppValues() throws {
        let decoder = JSONDecoder()

        let legacyT3 = try decoder.decode(SessionSurfaceFocus.self, from: Data(#""t3Code""#.utf8))
        let legacyVSCode = try decoder.decode(SessionSurfaceFocus.self, from: Data(#""vscode""#.utf8))

        XCTAssertEqual(legacyT3, .app(appID: NiriAppID.t3Code))
        XCTAssertEqual(legacyVSCode, .app(appID: NiriAppID.vscode))
    }

    func testSessionSurfaceFocusRoundTripsGenericAppValue() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let encoded = try encoder.encode(SessionSurfaceFocus.app(appID: "stub-app"))
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), #""app:stub-app""#)

        let decoded = try decoder.decode(SessionSurfaceFocus.self, from: encoded)
        XCTAssertEqual(decoded, .app(appID: "stub-app"))
    }

    private func makeSession(
        repoPath: String?,
        worktreePath: String?,
        lastLaunchCwd: String,
        lastKnownCwd: String? = nil,
        lastLaunchManifest: SessionLaunchManifest? = nil
    ) -> Session {
        let now = Date()
        return Session(
            id: UUID(),
            projectID: UUID(),
            title: "Session",
            hasCustomTitle: true,
            isPinned: false,
            createdAt: now,
            lastActiveAt: now,
            repoPath: repoPath,
            branchName: "main",
            worktreePath: worktreePath,
            worktreeState: nil,
            isWorktreeBacked: worktreePath != nil,
            shellPath: "/bin/zsh",
            lastLaunchCwd: lastLaunchCwd,
            attentionState: .normal,
            latestAttentionReason: nil,
            sandboxProfile: .fullAccess,
            sandboxEnforcementState: .unenforced,
            networkPolicy: .inherited,
            statusText: nil,
            lastKnownCwd: lastKnownCwd,
            browserState: nil,
            lastLaunchManifest: lastLaunchManifest,
            selectedVibeToolID: nil,
            agentActivity: nil,
            lastDiffStat: nil
        )
    }
}
