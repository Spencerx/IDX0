import Foundation

struct WorktreeInfo: Codable, Equatable {
    var repoPath: String
    var worktreePath: String
    var branchName: String
}

enum WorktreeState: String, Codable {
    case attached
    case missingOnDisk
    case dirty
    case clean
    case pendingDeletion
}
