import Foundation

enum BootstrapCoordinator {
    private static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestBundlePath"] != nil || environment["XCTestConfigurationFilePath"] != nil
    }

    static func makePaths(fileManager: FileManager = .default) throws -> FileSystemPaths {
        if !isRunningTests {
            let paths = try FileSystemPaths(fileManager: fileManager)
            try paths.ensureDirectories(fileManager: fileManager)
            return paths
        }

        let root = fileManager.temporaryDirectory
            .appendingPathComponent("idx0-app-tests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        if fileManager.fileExists(atPath: root.path) {
            try? fileManager.removeItem(at: root)
        }

        let paths = FileSystemPaths(
            appSupportDirectory: root,
            sessionsFile: root.appendingPathComponent("sessions.json", isDirectory: false),
            projectsFile: root.appendingPathComponent("projects.json", isDirectory: false),
            inboxFile: root.appendingPathComponent("inbox.json", isDirectory: false),
            settingsFile: root.appendingPathComponent("settings.json", isDirectory: false),
            runDirectory: root.appendingPathComponent("run", isDirectory: true),
            tempDirectory: root.appendingPathComponent("temp", isDirectory: true),
            worktreesDirectory: root.appendingPathComponent("worktrees", isDirectory: true)
        )
        try paths.ensureDirectories(fileManager: fileManager)
        return paths
    }
}
