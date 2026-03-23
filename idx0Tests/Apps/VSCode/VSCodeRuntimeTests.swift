import Foundation
import XCTest
@testable import idx0

@MainActor
final class VSCodeRuntimeTests: XCTestCase {
    func testPrepareSessionStateCreatesDirectoriesAndSettings() throws {
        let root = temporaryVSCodeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionID = UUID()
        let paths = VSCodeRuntimePaths(sessionID: sessionID, rootDirectoryOverride: root)
        let manager = VSCodeStateSnapshotManager()

        let state = try manager.prepareSessionState(
            paths: paths,
            profileSeedPath: "/Users/gal/Documents/Github/idx-web"
        )
        var isDirectory: ObjCBool = false

        XCTAssertTrue(FileManager.default.fileExists(atPath: state.userDataDir.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: state.extensionsDir.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)

        let settingsPath = state.userDataDir.appendingPathComponent("User/settings.json", isDirectory: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsPath.path))

        let settingsData = try Data(contentsOf: settingsPath)
        let settingsJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: settingsData) as? [String: Any])
        XCTAssertEqual(settingsJSON["debug.javascript.debugByLinkOptions"] as? String, "off")
        XCTAssertEqual(settingsJSON["python.languageServer"] as? String, "None")
        XCTAssertEqual(settingsJSON["security.workspace.trust.enabled"] as? Bool, false)
    }

    func testPrepareSessionStateReusesProfileAcrossSessionsForSameWorkspace() throws {
        let root = temporaryVSCodeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = VSCodeStateSnapshotManager()
        let workspacePath = "/Users/gal/Documents/Github/idx-web"

        let firstPaths = VSCodeRuntimePaths(sessionID: UUID(), rootDirectoryOverride: root)
        let firstState = try manager.prepareSessionState(paths: firstPaths, profileSeedPath: workspacePath)
        let firstSettingsPath = firstState.userDataDir.appendingPathComponent("User/settings.json", isDirectory: false)
        let firstSettingsData = try Data(contentsOf: firstSettingsPath)
        var firstRoot = try XCTUnwrap(try JSONSerialization.jsonObject(with: firstSettingsData) as? [String: Any])
        firstRoot["workbench.colorTheme"] = "Default Dark+"
        firstRoot["window.zoomLevel"] = 1.35
        let updated = try JSONSerialization.data(withJSONObject: firstRoot, options: [.prettyPrinted, .sortedKeys])
        try updated.write(to: firstSettingsPath, options: .atomic)

        manager.removeSessionState(paths: firstPaths)

        let secondPaths = VSCodeRuntimePaths(sessionID: UUID(), rootDirectoryOverride: root)
        let secondState = try manager.prepareSessionState(paths: secondPaths, profileSeedPath: workspacePath)
        XCTAssertEqual(secondState.userDataDir.path, firstState.userDataDir.path)

        let secondSettingsData = try Data(contentsOf: secondState.userDataDir.appendingPathComponent("User/settings.json", isDirectory: false))
        let secondRoot = try XCTUnwrap(try JSONSerialization.jsonObject(with: secondSettingsData) as? [String: Any])
        XCTAssertEqual(secondRoot["workbench.colorTheme"] as? String, "Default Dark+")
        let zoomValue = secondRoot["window.zoomLevel"] as? NSNumber
        let zoom = try XCTUnwrap(zoomValue?.doubleValue)
        XCTAssertEqual(zoom, 1.35, accuracy: 0.0001)
    }

    func testProvisionerReusesExistingInstallWithoutRunningCommands() async throws {
        let root = temporaryVSCodeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionID = UUID()
        let paths = VSCodeRuntimePaths(sessionID: sessionID, rootDirectoryOverride: root)
        try paths.ensureBaseDirectories()

        let manifest = VSCodeBuildManifest.default
        let platform = VSCodeBuildManifest.currentPlatformIdentifier()
        guard let artifact = manifest.artifact(forCurrentPlatform: platform) else {
            XCTFail("Missing test artifact for platform \(platform)")
            return
        }

        let runtimeDirectory = paths.runtimeVersionsDirectory.appendingPathComponent(artifact.extractDirectoryName, isDirectory: true)
        let executableURL = runtimeDirectory.appendingPathComponent(manifest.executableRelativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\necho ok\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        struct InstallRecordMirror: Codable {
            let runtimeName: String
            let version: String
            let platform: String
            let sha256: String
            let runtimeDirectoryName: String
            let executableRelativePath: String
            let installedAt: Date
        }

        let record = InstallRecordMirror(
            runtimeName: manifest.runtimeName,
            version: manifest.version,
            platform: platform,
            sha256: artifact.sha256,
            runtimeDirectoryName: artifact.extractDirectoryName,
            executableRelativePath: manifest.executableRelativePath,
            installedAt: Date()
        )
        let data = try JSONEncoder().encode(record)
        try data.write(to: paths.runtimeInstallRecordPath, options: .atomic)

        actor Counter {
            var value = 0

            func increment() {
                value += 1
            }

            func current() -> Int {
                value
            }
        }
        let counter = Counter()
        let runner = StubVSCodeProcessRunner { _, _, _ in
            await counter.increment()
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }

        let provisioner = OpenVSCodeProvisioner(processRunner: runner, fileManager: .default)
        let installed = try await provisioner.ensureRuntimeInstalled(manifest: manifest, paths: paths)
        let invocationCount = await counter.current()

        XCTAssertEqual(installed.path, runtimeDirectory.path)
        XCTAssertEqual(invocationCount, 0)
    }

    func testVSCodeRuntimeStateDisplayMessagesAreStable() {
        XCTAssertEqual(VSCodeTileRuntimeState.idle.displayMessage, "Ready")
        XCTAssertEqual(VSCodeTileRuntimeState.provisioning.displayMessage, "Preparing VS Code runtime...")
        XCTAssertEqual(VSCodeTileRuntimeState.downloading.displayMessage, "Downloading VS Code runtime...")
        XCTAssertEqual(VSCodeTileRuntimeState.extracting.displayMessage, "Installing VS Code runtime...")
        XCTAssertEqual(VSCodeTileRuntimeState.starting.displayMessage, "Starting VS Code...")
        XCTAssertEqual(VSCodeTileRuntimeState.live(urlString: "http://127.0.0.1:9999").displayMessage, "Live")
    }

    private func temporaryVSCodeRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("idx0-vscode-runtime-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private struct StubVSCodeProcessRunner: ProcessRunnerProtocol {
    let block: @Sendable (String, [String], String?) async throws -> ProcessResult

    init(block: @escaping @Sendable (String, [String], String?) async throws -> ProcessResult) {
        self.block = block
    }

    func run(executable: String, arguments: [String], currentDirectory: String?) async throws -> ProcessResult {
        try await block(executable, arguments, currentDirectory)
    }
}
