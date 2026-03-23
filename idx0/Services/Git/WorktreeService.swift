import Foundation

enum WorktreeServiceError: LocalizedError {
    case invalidFolder
    case invalidBranchName
    case invalidWorktreePath
    case worktreeNotFound
    case worktreeDirty
    case createFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFolder:
            return "The selected folder is invalid."
        case .invalidBranchName:
            return "Branch name cannot be empty."
        case .invalidWorktreePath:
            return "The selected worktree path is invalid."
        case .worktreeNotFound:
            return "That worktree does not belong to the selected repository."
        case .worktreeDirty:
            return "Worktree has local changes. Clean it before deletion."
        case .createFailed(let message):
            return message
        }
    }
}

protocol WorktreeServiceProtocol {
    func validateRepo(path: String) async throws -> GitRepoInfo
    func createWorktree(repoPath: String, branchName: String?, sessionTitle: String?) async throws -> WorktreeInfo
    func attachExistingWorktree(repoPath: String, worktreePath: String) async throws -> WorktreeInfo
    func listWorktrees(repoPath: String) async throws -> [WorktreeInfo]
    func inspectWorktree(repoPath: String, worktreePath: String) async throws -> WorktreeState
    func deleteWorktreeIfClean(repoPath: String, worktreePath: String) async throws
}

struct WorktreeService: WorktreeServiceProtocol {
    private let gitService: GitServiceProtocol
    private let paths: FileSystemPaths

    init(gitService: GitServiceProtocol, paths: FileSystemPaths) {
        self.gitService = gitService
        self.paths = paths
    }

    func validateRepo(path: String) async throws -> GitRepoInfo {
        try await gitService.repoInfo(for: path)
    }

    func listWorktrees(repoPath: String) async throws -> [WorktreeInfo] {
        try await gitService.listWorktrees(repoPath: repoPath)
    }

    func attachExistingWorktree(repoPath: String, worktreePath: String) async throws -> WorktreeInfo {
        let info = try await gitService.repoInfo(for: repoPath)
        let normalizedPath = URL(fileURLWithPath: worktreePath).standardizedFileURL.path

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalizedPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw WorktreeServiceError.invalidWorktreePath
        }

        let worktrees = try await gitService.listWorktrees(repoPath: info.topLevelPath)
        guard let match = worktrees.first(where: {
            URL(fileURLWithPath: $0.worktreePath).standardizedFileURL.path == normalizedPath
        }) else {
            throw WorktreeServiceError.worktreeNotFound
        }

        return WorktreeInfo(
            repoPath: info.topLevelPath,
            worktreePath: match.worktreePath,
            branchName: match.branchName
        )
    }

    func createWorktree(repoPath: String, branchName: String?, sessionTitle: String?) async throws -> WorktreeInfo {
        let info = try await gitService.repoInfo(for: repoPath)

        let resolvedBranch: String
        if let branchName,
           !branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedBranch = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            resolvedBranch = BranchNameGenerator.generate(
                sessionTitle: sessionTitle,
                repoName: info.repoName
            )
        }

        guard !resolvedBranch.isEmpty else {
            throw WorktreeServiceError.invalidBranchName
        }

        let worktreePath = uniqueWorktreePath(repoName: info.repoName, branchName: resolvedBranch)

        do {
            return try await gitService.createWorktree(
                repoPath: info.topLevelPath,
                branchName: resolvedBranch,
                worktreePath: worktreePath
            )
        } catch {
            throw WorktreeServiceError.createFailed(error.localizedDescription)
        }
    }

    func inspectWorktree(repoPath: String, worktreePath: String) async throws -> WorktreeState {
        let info = try await gitService.repoInfo(for: repoPath)
        let normalizedPath = URL(fileURLWithPath: worktreePath).standardizedFileURL.path

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalizedPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .missingOnDisk
        }

        let worktrees = try await gitService.listWorktrees(repoPath: info.topLevelPath)
        guard worktrees.contains(where: {
            URL(fileURLWithPath: $0.worktreePath).standardizedFileURL.path == normalizedPath
        }) else {
            throw WorktreeServiceError.worktreeNotFound
        }

        let status = try await gitService.statusPorcelain(path: normalizedPath)
        return status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .clean : .dirty
    }

    func deleteWorktreeIfClean(repoPath: String, worktreePath: String) async throws {
        let state = try await inspectWorktree(repoPath: repoPath, worktreePath: worktreePath)
        switch state {
        case .clean:
            let info = try await gitService.repoInfo(for: repoPath)
            try await gitService.removeWorktree(
                repoPath: info.topLevelPath,
                worktreePath: URL(fileURLWithPath: worktreePath).standardizedFileURL.path
            )
        case .dirty:
            throw WorktreeServiceError.worktreeDirty
        case .missingOnDisk:
            throw WorktreeServiceError.invalidWorktreePath
        default:
            throw WorktreeServiceError.worktreeNotFound
        }
    }

    private func uniqueWorktreePath(repoName: String, branchName: String) -> String {
        let safeRepo = BranchNameGenerator.slugify(repoName)
        let safeBranch = BranchNameGenerator.slugify(branchName)
        let root = paths.worktreesDirectory
            .appendingPathComponent(safeRepo, isDirectory: true)

        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var candidate = root.appendingPathComponent(safeBranch, isDirectory: true)
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(safeBranch)-\(suffix)", isDirectory: true)
            suffix += 1
        }

        return candidate.path
    }
}
