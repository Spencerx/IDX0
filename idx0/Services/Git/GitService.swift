import Foundation

struct GitRepoInfo: Equatable {
    let topLevelPath: String
    let currentBranch: String?
    let repoName: String
}

enum GitServiceError: LocalizedError {
    case invalidPath(String)
    case notGitRepository(String)
    case commandFailed(String)
    case branchAlreadyExists

    var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return "The path does not exist: \(path)"
        case .notGitRepository:
            return "This folder is not a Git repository. Choose another folder or turn off worktree creation."
        case .commandFailed(let message):
            return message
        case .branchAlreadyExists:
            return "Branch already exists. Choose a different branch name or attach an existing worktree."
        }
    }
}

protocol GitServiceProtocol {
    func repoInfo(for path: String) async throws -> GitRepoInfo
    func currentBranch(repoPath: String) async throws -> String?
    func currentCommitSHA(repoPath: String) async throws -> String?
    func localBranches(repoPath: String) async throws -> [String]
    func listWorktrees(repoPath: String) async throws -> [WorktreeInfo]
    func createWorktree(repoPath: String, branchName: String, worktreePath: String) async throws -> WorktreeInfo
    func statusPorcelain(path: String) async throws -> String
    func removeWorktree(repoPath: String, worktreePath: String) async throws
    func diffNameStatus(path: String) async throws -> [ChangedFileSummary]
    func diffNameStatus(path: String, between leftRef: String, and rightRef: String) async throws -> [ChangedFileSummary]
    func diffStat(path: String) async throws -> DiffStat?
    func diffStat(path: String, between leftRef: String, and rightRef: String) async throws -> DiffStat?
}

struct GitService: GitServiceProtocol {
    private let runner: ProcessRunnerProtocol

    init(runner: ProcessRunnerProtocol = ProcessRunner()) {
        self.runner = runner
    }

    func repoInfo(for path: String) async throws -> GitRepoInfo {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw GitServiceError.invalidPath(path)
        }

        let topResult = try await runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", path, "rev-parse", "--show-toplevel"],
            currentDirectory: nil
        )

        guard topResult.exitCode == 0, !topResult.stdout.isEmpty else {
            throw GitServiceError.notGitRepository(path)
        }

        let repoRoot = topResult.stdout
        let branch = try await currentBranch(repoPath: repoRoot)
        let repoName = URL(fileURLWithPath: repoRoot).lastPathComponent
        return GitRepoInfo(topLevelPath: repoRoot, currentBranch: branch, repoName: repoName)
    }

    func currentBranch(repoPath: String) async throws -> String? {
        let result = try await runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", repoPath, "branch", "--show-current"],
            currentDirectory: nil
        )

        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.isEmpty ? "Unable to resolve current branch." : result.stderr)
        }

        return result.stdout.isEmpty ? nil : result.stdout
    }

    func currentCommitSHA(repoPath: String) async throws -> String? {
        let result = try await runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", repoPath, "rev-parse", "HEAD"],
            currentDirectory: nil
        )
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.isEmpty ? "Unable to resolve commit SHA." : result.stderr)
        }
        return result.stdout.isEmpty ? nil : result.stdout
    }

    func localBranches(repoPath: String) async throws -> [String] {
        let result = try await runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", repoPath, "branch", "--format=%(refname:short)"],
            currentDirectory: nil
        )

        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.isEmpty ? "Unable to list local branches." : result.stderr)
        }

        return result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
    }

    func listWorktrees(repoPath: String) async throws -> [WorktreeInfo] {
        let result = try await runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", repoPath, "worktree", "list", "--porcelain"],
            currentDirectory: nil
        )

        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.isEmpty ? "Unable to list worktrees." : result.stderr)
        }

        return parseWorktreeList(result.stdout, repoPath: repoPath)
    }

    func createWorktree(repoPath: String, branchName: String, worktreePath: String) async throws -> WorktreeInfo {
        let result = try await runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", repoPath, "worktree", "add", worktreePath, "-b", branchName],
            currentDirectory: nil
        )

        guard result.exitCode == 0 else {
            let joinedError = [result.stdout, result.stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
                .lowercased()
            if joinedError.contains("already exists") || joinedError.contains("exists") {
                throw GitServiceError.branchAlreadyExists
            }
            throw GitServiceError.commandFailed(result.stderr.isEmpty ? "Failed to create worktree." : result.stderr)
        }

        return WorktreeInfo(repoPath: repoPath, worktreePath: worktreePath, branchName: branchName)
    }

    func statusPorcelain(path: String) async throws -> String {
        let result = try await runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", path, "status", "--porcelain"],
            currentDirectory: nil
        )

        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.isEmpty ? "Unable to inspect worktree status." : result.stderr)
        }

        return result.stdout
    }

    func removeWorktree(repoPath: String, worktreePath: String) async throws {
        let result = try await runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", repoPath, "worktree", "remove", worktreePath],
            currentDirectory: nil
        )

        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.isEmpty ? "Unable to remove worktree." : result.stderr)
        }
    }

    func diffNameStatus(path: String) async throws -> [ChangedFileSummary] {
        let nameStatus = try await runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", path, "diff", "--name-status"],
            currentDirectory: nil
        )
        guard nameStatus.exitCode == 0 else {
            throw GitServiceError.commandFailed(nameStatus.stderr.isEmpty ? "Unable to inspect changed files." : nameStatus.stderr)
        }

        let numstat = try await runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", path, "diff", "--numstat"],
            currentDirectory: nil
        )
        guard numstat.exitCode == 0 else {
            throw GitServiceError.commandFailed(numstat.stderr.isEmpty ? "Unable to inspect line stats." : numstat.stderr)
        }

        return parseChangedFileSummary(nameStatusOutput: nameStatus.stdout, numstatOutput: numstat.stdout)
    }

    func diffNameStatus(path: String, between leftRef: String, and rightRef: String) async throws -> [ChangedFileSummary] {
        let refRange = "\(leftRef)...\(rightRef)"
        let nameStatus = try await runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", path, "diff", "--name-status", refRange],
            currentDirectory: nil
        )
        guard nameStatus.exitCode == 0 else {
            throw GitServiceError.commandFailed(nameStatus.stderr.isEmpty ? "Unable to inspect changed files between refs." : nameStatus.stderr)
        }

        let numstat = try await runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", path, "diff", "--numstat", refRange],
            currentDirectory: nil
        )
        guard numstat.exitCode == 0 else {
            throw GitServiceError.commandFailed(numstat.stderr.isEmpty ? "Unable to inspect line stats between refs." : numstat.stderr)
        }

        return parseChangedFileSummary(nameStatusOutput: nameStatus.stdout, numstatOutput: numstat.stdout)
    }

    func diffStat(path: String) async throws -> DiffStat? {
        let result = try await runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", path, "diff", "--shortstat"],
            currentDirectory: nil
        )
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.isEmpty ? "Unable to inspect diff stat." : result.stderr)
        }

        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return DiffStat(filesChanged: 0, additions: 0, deletions: 0)
        }

        let files = parseFirstInteger(matching: #"(\d+)\s+files?\s+changed"#, text: trimmed) ?? 0
        let additions = parseFirstInteger(matching: #"(\d+)\s+insertions?\(\+\)"#, text: trimmed) ?? 0
        let deletions = parseFirstInteger(matching: #"(\d+)\s+deletions?\(-\)"#, text: trimmed) ?? 0
        return DiffStat(filesChanged: files, additions: additions, deletions: deletions)
    }

    func diffStat(path: String, between leftRef: String, and rightRef: String) async throws -> DiffStat? {
        let refRange = "\(leftRef)...\(rightRef)"
        let result = try await runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", path, "diff", "--shortstat", refRange],
            currentDirectory: nil
        )
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.isEmpty ? "Unable to inspect diff stat between refs." : result.stderr)
        }

        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return DiffStat(filesChanged: 0, additions: 0, deletions: 0)
        }

        let files = parseFirstInteger(matching: #"(\d+)\s+files?\s+changed"#, text: trimmed) ?? 0
        let additions = parseFirstInteger(matching: #"(\d+)\s+insertions?\(\+\)"#, text: trimmed) ?? 0
        let deletions = parseFirstInteger(matching: #"(\d+)\s+deletions?\(-\)"#, text: trimmed) ?? 0
        return DiffStat(filesChanged: files, additions: additions, deletions: deletions)
    }

    func fullDiff(path: String) async throws -> String {
        let result = try await runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", path, "diff"],
            currentDirectory: nil
        )
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.isEmpty ? "Unable to generate diff." : result.stderr)
        }
        return result.stdout
    }

    func fullDiff(path: String, since commitSHA: String) async throws -> String {
        // Combined: committed changes since checkpoint + uncommitted changes
        let committed = try await runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", path, "diff", "\(commitSHA)...HEAD"],
            currentDirectory: nil
        )
        let uncommitted = try await runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", path, "diff"],
            currentDirectory: nil
        )
        var combined = ""
        if committed.exitCode == 0, !committed.stdout.isEmpty {
            combined += committed.stdout
        }
        if uncommitted.exitCode == 0, !uncommitted.stdout.isEmpty {
            if !combined.isEmpty { combined += "\n" }
            combined += uncommitted.stdout
        }
        return combined
    }

    private func parseWorktreeList(_ text: String, repoPath: String) -> [WorktreeInfo] {
        var worktrees: [WorktreeInfo] = []
        let blocks = text.components(separatedBy: "\n\n")

        for block in blocks where !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var path: String?
            var branch: String?

            for line in block.components(separatedBy: .newlines) {
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("branch ") {
                    let raw = String(line.dropFirst("branch ".count))
                    branch = raw.replacingOccurrences(of: "refs/heads/", with: "")
                }
            }

            if let path, let branch {
                worktrees.append(WorktreeInfo(repoPath: repoPath, worktreePath: path, branchName: branch))
            }
        }

        return worktrees
    }

    private func parseChangedFileSummary(nameStatusOutput: String, numstatOutput: String) -> [ChangedFileSummary] {
        var countsByPath: [String: (Int?, Int?)] = [:]
        for line in numstatOutput.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count >= 3 else { continue }
            let additions = Int(parts[0])
            let deletions = Int(parts[1])
            let pathPart = String(parts[2])
            countsByPath[pathPart] = (additions, deletions)
        }

        var summaries: [ChangedFileSummary] = []
        for line in nameStatusOutput.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count >= 2 else { continue }
            let status = String(parts[0])
            let filePath = String(parts[1])
            let counts = countsByPath[filePath]
            summaries.append(
                ChangedFileSummary(
                    path: filePath,
                    additions: counts?.0 ?? nil,
                    deletions: counts?.1 ?? nil,
                    status: status
                )
            )
        }
        return summaries
    }

    private func parseFirstInteger(matching pattern: String, text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else {
            return nil
        }
        guard let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[swiftRange])
    }
}
