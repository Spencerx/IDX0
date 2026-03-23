import Foundation

struct SessionCreationRequest {
    var title: String?
    var repoPath: String?
    var createWorktree: Bool
    var branchName: String?
    var existingWorktreePath: String?
    var shellPath: String?
    var sandboxProfile: SandboxProfile?
    var networkPolicy: NetworkPolicy?
    var launchToolID: String?

    init(
        title: String? = nil,
        repoPath: String? = nil,
        createWorktree: Bool = false,
        branchName: String? = nil,
        existingWorktreePath: String? = nil,
        shellPath: String? = nil,
        sandboxProfile: SandboxProfile? = nil,
        networkPolicy: NetworkPolicy? = nil,
        launchToolID: String? = nil
    ) {
        self.title = title
        self.repoPath = repoPath
        self.createWorktree = createWorktree
        self.branchName = branchName
        self.existingWorktreePath = existingWorktreePath
        self.shellPath = shellPath
        self.sandboxProfile = sandboxProfile
        self.networkPolicy = networkPolicy
        self.launchToolID = launchToolID
    }
}
