import Combine
import CommonCrypto
import Foundation

@MainActor
final class GitMonitor {
    private let sessionService: SessionService
    private let workflowService: WorkflowService
    private let pollInterval: TimeInterval

    private var lastKnownSHAs: [UUID: String] = [:]
    private var lastKnownStatusHash: [UUID: String] = [:]
    private var pollingTask: Task<Void, Never>?
    private var sessionsCancellable: AnyCancellable?

    init(
        sessionService: SessionService,
        workflowService: WorkflowService,
        pollInterval: TimeInterval = 15.0
    ) {
        self.sessionService = sessionService
        self.workflowService = workflowService
        self.pollInterval = pollInterval
    }

    func start() {
        sessionsCancellable = sessionService.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                guard let self else { return }
                self.reconcileSessions(sessions)
            }

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 15))
                guard !Task.isCancelled else { break }
                await self?.pollAll()
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        sessionsCancellable?.cancel()
        sessionsCancellable = nil
        lastKnownSHAs.removeAll()
        lastKnownStatusHash.removeAll()
    }

    // MARK: - Private

    private func reconcileSessions(_ sessions: [Session]) {
        let activeIDs = Set(sessions.compactMap { session -> UUID? in
            guard session.repoPath != nil else { return nil }
            return session.id
        })

        for id in lastKnownSHAs.keys where !activeIDs.contains(id) {
            lastKnownSHAs.removeValue(forKey: id)
            lastKnownStatusHash.removeValue(forKey: id)
        }

        for session in sessions {
            guard session.repoPath != nil, lastKnownSHAs[session.id] == nil else { continue }
            let sessionID = session.id
            let path = session.worktreePath ?? session.repoPath ?? ""
            guard !path.isEmpty else { continue }
            // Mark immediately to prevent re-seeding
            lastKnownSHAs[sessionID] = ""
            lastKnownStatusHash[sessionID] = ""
            Task {
                let git = GitService()
                let sha = try? await git.currentCommitSHA(repoPath: path)
                let status = try? await git.statusPorcelain(path: path)
                self.lastKnownSHAs[sessionID] = sha ?? ""
                self.lastKnownStatusHash[sessionID] = Self.hash(status ?? "")
            }
        }
    }

    private func pollAll() async {
        let trackedSHAs = lastKnownSHAs
        let git = GitService()

        for (sessionID, previousSHA) in trackedSHAs {
            guard let session = sessionService.sessions.first(where: { $0.id == sessionID }) else {
                lastKnownSHAs.removeValue(forKey: sessionID)
                lastKnownStatusHash.removeValue(forKey: sessionID)
                continue
            }

            let path = session.worktreePath ?? session.repoPath ?? ""
            guard !path.isEmpty else { continue }

            // Check commit SHA
            let currentSHA = try? await git.currentCommitSHA(repoPath: path)
            if let currentSHA, currentSHA != previousSHA, !previousSHA.isEmpty {
                lastKnownSHAs[sessionID] = currentSHA
                await createAutoCheckpoint(
                    sessionID: sessionID,
                    title: "Commit \(String(currentSHA.prefix(7)))",
                    summary: "New commit detected"
                )
            } else if let currentSHA, previousSHA.isEmpty {
                lastKnownSHAs[sessionID] = currentSHA
            }

            // Check unstaged/staged changes
            let status = (try? await git.statusPorcelain(path: path)) ?? ""
            let currentHash = Self.hash(status)
            let previousHash = lastKnownStatusHash[sessionID] ?? ""

            if currentHash != previousHash, !previousHash.isEmpty {
                lastKnownStatusHash[sessionID] = currentHash
                // Only create checkpoint if there are actual changes (non-empty status)
                if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let fileCount = status.split(separator: "\n").count
                    await createAutoCheckpoint(
                        sessionID: sessionID,
                        title: "\(fileCount) file\(fileCount == 1 ? "" : "s") changed",
                        summary: "Unstaged changes detected"
                    )
                }
            } else if previousHash.isEmpty {
                lastKnownStatusHash[sessionID] = currentHash
            }
        }
    }

    private func createAutoCheckpoint(sessionID: UUID, title: String, summary: String) async {
        do {
            _ = try await workflowService.createManualCheckpoint(
                sessionID: sessionID,
                title: title,
                summary: summary,
                requestReview: false,
                source: .autoCommit
            )
        } catch {
            Logger.error("GitMonitor: failed to create auto-checkpoint for \(sessionID): \(error)")
        }
    }

    private static func hash(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
