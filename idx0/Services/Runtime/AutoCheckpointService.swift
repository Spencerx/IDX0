import Foundation

@MainActor
final class AutoCheckpointService: ObservableObject {
    struct Checkpoint: Identifiable, Codable, Equatable {
        let id: UUID
        let sessionID: UUID
        let repoPath: String
        let commitSHA: String
        let stashRef: String?
        let branchName: String?
        let createdAt: Date
        let diffStat: DiffStat?
    }

    static let maxCheckpointsPerSession = 5

    @Published private(set) var checkpoints: [UUID: [Checkpoint]] = [:]

    private let gitService: GitServiceProtocol
    private let storageURL: URL

    init(gitService: GitServiceProtocol, storageURL: URL) {
        self.gitService = gitService
        self.storageURL = storageURL
        loadFromDisk()
    }

    // MARK: - Create

    func createCheckpoint(sessionID: UUID, repoPath: String) async {
        do {
            nonisolated(unsafe) let git = gitService
            guard let sha = try await git.currentCommitSHA(repoPath: repoPath) else { return }

            let branch = try? await git.currentBranch(repoPath: repoPath)

            // Create stash object for uncommitted changes (doesn't modify working tree)
            let stashRef = await createStashObject(repoPath: repoPath)

            let stat = try? await git.diffStat(path: repoPath)

            let checkpoint = Checkpoint(
                id: UUID(),
                sessionID: sessionID,
                repoPath: repoPath,
                commitSHA: sha,
                stashRef: stashRef,
                branchName: branch,
                createdAt: Date(),
                diffStat: stat
            )

            var sessionCheckpoints = checkpoints[sessionID] ?? []
            sessionCheckpoints.append(checkpoint)

            // Prune oldest if over limit
            if sessionCheckpoints.count > Self.maxCheckpointsPerSession {
                sessionCheckpoints = Array(sessionCheckpoints.suffix(Self.maxCheckpointsPerSession))
            }

            checkpoints[sessionID] = sessionCheckpoints
            saveToDisk()
        } catch {
            Logger.error("Auto-checkpoint failed for session \(sessionID): \(error.localizedDescription)")
        }
    }

    // MARK: - Restore

    func restoreCheckpoint(_ checkpoint: Checkpoint) async throws {
        let runner = ProcessRunner()

        // Reset to the checkpoint commit
        let resetResult = try await runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", checkpoint.repoPath, "reset", "--hard", checkpoint.commitSHA],
            currentDirectory: nil
        )

        guard resetResult.exitCode == 0 else {
            throw CheckpointError.restoreFailed(resetResult.stderr)
        }

        // Apply stashed changes if available
        if let stashRef = checkpoint.stashRef {
            let stashResult = try await runner.run(
                executable: "/usr/bin/git",
                arguments: ["-C", checkpoint.repoPath, "stash", "apply", stashRef],
                currentDirectory: nil
            )

            if stashResult.exitCode != 0 {
                Logger.warning("Stash apply failed (changes may conflict): \(stashResult.stderr)")
            }
        }
    }

    // MARK: - Query

    func checkpointsForSession(_ sessionID: UUID) -> [Checkpoint] {
        checkpoints[sessionID] ?? []
    }

    func latestCheckpoint(for sessionID: UUID) -> Checkpoint? {
        checkpoints[sessionID]?.last
    }

    // MARK: - Cleanup

    func removeCheckpoints(for sessionID: UUID) {
        checkpoints.removeValue(forKey: sessionID)
        saveToDisk()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let stored = try decoder.decode([UUID: [Checkpoint]].self, from: data)
            checkpoints = stored
        } catch {
            Logger.error("Failed to load auto-checkpoints: \(error.localizedDescription)")
        }
    }

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(checkpoints)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Logger.error("Failed to save auto-checkpoints: \(error.localizedDescription)")
        }
    }

    // MARK: - Git Helpers

    private func createStashObject(repoPath: String) async -> String? {
        let runner = ProcessRunner()
        do {
            // Check if there are uncommitted changes
            nonisolated(unsafe) let git = gitService
            let status = try await git.statusPorcelain(path: repoPath)
            guard !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            // git stash create makes a stash commit object without modifying the working tree
            let result = try await runner.run(
                executable: "/usr/bin/git",
                arguments: ["-C", repoPath, "stash", "create", "idx0-auto-checkpoint"],
                currentDirectory: nil
            )

            let ref = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return ref.isEmpty ? nil : ref
        } catch {
            return nil
        }
    }

    enum CheckpointError: LocalizedError {
        case restoreFailed(String)

        var errorDescription: String? {
            switch self {
            case .restoreFailed(let msg):
                return "Failed to restore checkpoint: \(msg)"
            }
        }
    }
}
