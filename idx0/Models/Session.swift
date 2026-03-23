import Foundation

enum AgentActivity: Codable, Equatable {
    case active(description: String)
    case waiting(description: String)
    case completed(description: String)
    case error(description: String)

    var description: String {
        switch self {
        case .active(let d), .waiting(let d), .completed(let d), .error(let d):
            return d
        }
    }

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    var isWaiting: Bool {
        if case .waiting = self { return true }
        return false
    }
}

enum AttentionReason: String, Codable, CaseIterable {
    case needsInput
    case completed
    case error
    case notification

    var urgencyRank: Int {
        switch self {
        case .error:
            return 0
        case .needsInput:
            return 1
        case .completed:
            return 2
        case .notification:
            return 3
        }
    }

    var displayLabel: String {
        switch self {
        case .needsInput:
            return "Needs Input"
        case .completed:
            return "Completed"
        case .error:
            return "Error"
        case .notification:
            return "Notification"
        }
    }
}

enum SandboxProfile: String, Codable, CaseIterable {
    case fullAccess
    case worktreeWrite
    case worktreeAndTemp

    var displayLabel: String {
        switch self {
        case .fullAccess:
            return "Full Access"
        case .worktreeWrite:
            return "Worktree Write"
        case .worktreeAndTemp:
            return "Worktree + Temp"
        }
    }
}

enum NetworkPolicy: String, Codable, CaseIterable {
    case inherited
    case disabled

    var displayLabel: String {
        switch self {
        case .inherited:
            return "Network On"
        case .disabled:
            return "Network Off"
        }
    }
}

enum SandboxEnforcementState: String, Codable, CaseIterable {
    case unenforced
    case enforced
    case degraded

    var displayLabel: String {
        switch self {
        case .unenforced:
            return "Unenforced"
        case .enforced:
            return "Enforced"
        case .degraded:
            return "Degraded"
        }
    }
}

enum SessionSurfaceFocus: Codable, Equatable, Hashable {
    case terminal
    case browser
    case app(appID: String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "terminal":
            self = .terminal
        case "browser":
            self = .browser
        case "t3Code":
            // Legacy persisted value.
            self = .app(appID: "t3-code")
        case "vscode":
            // Legacy persisted value.
            self = .app(appID: "vscode")
        default:
            if value.hasPrefix("app:") {
                let appID = String(value.dropFirst("app:".count))
                guard !appID.isEmpty else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Invalid app surface value: \(value)"
                    )
                }
                self = .app(appID: appID)
                return
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown session surface focus value: \(value)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let encoded: String

        switch self {
        case .terminal:
            encoded = "terminal"
        case .browser:
            encoded = "browser"
        case .app(let appID):
            encoded = "app:\(appID)"
        }

        try container.encode(encoded)
    }
}

struct SessionLaunchManifest: Codable, Equatable {
    let sessionID: UUID
    let cwd: String
    let shellPath: String
    let repoPath: String?
    let worktreePath: String?
    let sandboxProfile: SandboxProfile
    let networkPolicy: NetworkPolicy
    let tempRoot: String?
    let environment: [String: String]
    let projectID: String?
    let ipcSocketPath: String?
    /// When set, the launch wrapper exec's this tool directly instead of loading an interactive shell.
    /// This bypasses zshrc and makes Cmd+N near-instant for known CLI tools.
    let directLaunchToolPath: String?

    init(
        sessionID: UUID,
        cwd: String,
        shellPath: String,
        repoPath: String?,
        worktreePath: String?,
        sandboxProfile: SandboxProfile,
        networkPolicy: NetworkPolicy,
        tempRoot: String?,
        environment: [String: String],
        projectID: String?,
        ipcSocketPath: String?,
        directLaunchToolPath: String? = nil
    ) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.shellPath = shellPath
        self.repoPath = repoPath
        self.worktreePath = worktreePath
        self.sandboxProfile = sandboxProfile
        self.networkPolicy = networkPolicy
        self.tempRoot = tempRoot
        self.environment = environment
        self.projectID = projectID
        self.ipcSocketPath = ipcSocketPath
        self.directLaunchToolPath = directLaunchToolPath
    }
}

struct LaunchHelperResult: Codable, Equatable {
    let enforcementState: SandboxEnforcementState
    let message: String?
}

enum SplitSide: String, Codable, CaseIterable {
    case right
    case bottom
}

struct BrowserSurfaceState: Codable, Equatable {
    var isVisible: Bool
    var currentURL: String?
    var splitSide: SplitSide
    var splitFraction: Double

    init(
        isVisible: Bool = false,
        currentURL: String? = nil,
        splitSide: SplitSide = .right,
        splitFraction: Double = 0.5
    ) {
        self.isVisible = isVisible
        self.currentURL = currentURL
        self.splitSide = splitSide
        self.splitFraction = min(0.9, max(0.1, splitFraction))
    }
}

struct ProjectGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var repoPath: String?
    var isCollapsed: Bool
    var sessionIDs: [UUID]
}

struct AttentionItem: Identifiable, Codable, Equatable {
    let id: UUID
    let sessionID: UUID
    let reason: AttentionReason
    let message: String?
    let createdAt: Date
    var isResolved: Bool
}

struct Session: Identifiable, Codable, Equatable {
    let id: UUID
    var projectID: UUID?
    var title: String
    var hasCustomTitle: Bool
    var isPinned: Bool
    var createdAt: Date
    var lastActiveAt: Date
    var repoPath: String?
    var branchName: String?
    var worktreePath: String?
    var worktreeState: WorktreeState?
    var isWorktreeBacked: Bool
    var shellPath: String
    var lastLaunchCwd: String
    var attentionState: SessionAttentionState
    var latestAttentionReason: AttentionReason?
    var sandboxProfile: SandboxProfile
    var sandboxEnforcementState: SandboxEnforcementState
    var networkPolicy: NetworkPolicy
    var statusText: String?
    var lastKnownCwd: String?
    var browserState: BrowserSurfaceState?
    var lastLaunchManifest: SessionLaunchManifest?
    var selectedVibeToolID: String?
    var agentActivity: AgentActivity?
    var lastDiffStat: DiffStat?

    init(
        id: UUID,
        projectID: UUID? = nil,
        title: String,
        hasCustomTitle: Bool,
        isPinned: Bool = false,
        createdAt: Date,
        lastActiveAt: Date,
        repoPath: String?,
        branchName: String?,
        worktreePath: String?,
        worktreeState: WorktreeState? = nil,
        isWorktreeBacked: Bool,
        shellPath: String,
        lastLaunchCwd: String? = nil,
        attentionState: SessionAttentionState,
        latestAttentionReason: AttentionReason? = nil,
        sandboxProfile: SandboxProfile = .fullAccess,
        sandboxEnforcementState: SandboxEnforcementState = .unenforced,
        networkPolicy: NetworkPolicy = .inherited,
        statusText: String?,
        lastKnownCwd: String?,
        browserState: BrowserSurfaceState? = nil,
        lastLaunchManifest: SessionLaunchManifest? = nil,
        selectedVibeToolID: String? = nil,
        agentActivity: AgentActivity? = nil,
        lastDiffStat: DiffStat? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.hasCustomTitle = hasCustomTitle
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.repoPath = repoPath
        self.branchName = branchName
        self.worktreePath = worktreePath
        self.worktreeState = worktreeState
        self.isWorktreeBacked = isWorktreeBacked
        self.shellPath = shellPath
        self.lastLaunchCwd = lastLaunchCwd
            ?? worktreePath
            ?? repoPath
            ?? lastKnownCwd
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        self.attentionState = attentionState
        self.latestAttentionReason = latestAttentionReason
        self.sandboxProfile = sandboxProfile
        self.sandboxEnforcementState = sandboxEnforcementState
        self.networkPolicy = networkPolicy
        self.statusText = statusText
        self.lastKnownCwd = lastKnownCwd
        self.browserState = browserState
        self.lastLaunchManifest = lastLaunchManifest
        self.selectedVibeToolID = selectedVibeToolID
        self.agentActivity = agentActivity
        self.lastDiffStat = lastDiffStat
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case projectID
        case title
        case hasCustomTitle
        case isPinned
        case createdAt
        case lastActiveAt
        case repoPath
        case branchName
        case worktreePath
        case worktreeState
        case isWorktreeBacked
        case shellPath
        case lastLaunchCwd
        case attentionState
        case latestAttentionReason
        case sandboxProfile
        case sandboxEnforcementState
        case networkPolicy
        case statusText
        case lastKnownCwd
        case browserState
        case lastLaunchManifest
        case selectedVibeToolID
        case agentActivity
        case lastDiffStat
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
        title = try container.decode(String.self, forKey: .title)
        hasCustomTitle = try container.decode(Bool.self, forKey: .hasCustomTitle)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastActiveAt = try container.decode(Date.self, forKey: .lastActiveAt)
        repoPath = try container.decodeIfPresent(String.self, forKey: .repoPath)
        branchName = try container.decodeIfPresent(String.self, forKey: .branchName)
        worktreePath = try container.decodeIfPresent(String.self, forKey: .worktreePath)
        worktreeState = try container.decodeIfPresent(WorktreeState.self, forKey: .worktreeState)
        isWorktreeBacked = try container.decode(Bool.self, forKey: .isWorktreeBacked)
        shellPath = try container.decode(String.self, forKey: .shellPath)
        attentionState = try container.decodeIfPresent(SessionAttentionState.self, forKey: .attentionState) ?? .normal
        latestAttentionReason = try container.decodeIfPresent(AttentionReason.self, forKey: .latestAttentionReason)
        sandboxProfile = try container.decodeIfPresent(SandboxProfile.self, forKey: .sandboxProfile) ?? .fullAccess
        sandboxEnforcementState = try container.decodeIfPresent(SandboxEnforcementState.self, forKey: .sandboxEnforcementState) ?? .unenforced
        networkPolicy = try container.decodeIfPresent(NetworkPolicy.self, forKey: .networkPolicy) ?? .inherited
        statusText = try container.decodeIfPresent(String.self, forKey: .statusText)
        lastKnownCwd = try container.decodeIfPresent(String.self, forKey: .lastKnownCwd)
        browserState = try container.decodeIfPresent(BrowserSurfaceState.self, forKey: .browserState)
        lastLaunchManifest = try container.decodeIfPresent(SessionLaunchManifest.self, forKey: .lastLaunchManifest)
        selectedVibeToolID = try container.decodeIfPresent(String.self, forKey: .selectedVibeToolID)
        agentActivity = try container.decodeIfPresent(AgentActivity.self, forKey: .agentActivity)
        lastDiffStat = try container.decodeIfPresent(DiffStat.self, forKey: .lastDiffStat)
        lastLaunchCwd = try container.decodeIfPresent(String.self, forKey: .lastLaunchCwd)
            ?? worktreePath
            ?? repoPath
            ?? lastKnownCwd
            ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    var launchDirectory: String {
        if let worktreePath, !worktreePath.isEmpty {
            return worktreePath
        }
        if let repoPath, !repoPath.isEmpty {
            return repoPath
        }
        if !lastLaunchCwd.isEmpty {
            return lastLaunchCwd
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    var launchManifest: SessionLaunchManifest {
        if let lastLaunchManifest {
            return lastLaunchManifest
        }
        return SessionLaunchManifest(
            sessionID: id,
            cwd: launchDirectory,
            shellPath: shellPath,
            repoPath: repoPath,
            worktreePath: worktreePath,
            sandboxProfile: sandboxProfile,
            networkPolicy: networkPolicy,
            tempRoot: nil,
            environment: [:],
            projectID: projectID?.uuidString,
            ipcSocketPath: lastLaunchManifest?.ipcSocketPath
        )
    }

    var subtitle: String {
        if let repoPath {
            return URL(fileURLWithPath: repoPath).lastPathComponent
        }
        if let lastKnownCwd {
            return URL(fileURLWithPath: lastKnownCwd).lastPathComponent
        }
        return URL(fileURLWithPath: lastLaunchCwd).lastPathComponent
    }
}
