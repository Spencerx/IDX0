import Foundation

enum SessionAttentionState: String, Codable, CaseIterable {
    case normal
    case active
    case needsAttention
}
