import Foundation

struct VibeCLITool: Identifiable, Codable, Equatable {
    let id: String
    let displayName: String
    let executableName: String
    let launchCommand: String
    var isInstalled: Bool
    var resolvedPath: String?

    static let known: [VibeCLITool] = [
        VibeCLITool(id: "gemini-cli", displayName: "Gemini CLI", executableName: "gemini-cli", launchCommand: "gemini-cli", isInstalled: false, resolvedPath: nil),
        VibeCLITool(id: "claude", displayName: "Claude Code", executableName: "claude", launchCommand: "claude", isInstalled: false, resolvedPath: nil),
        VibeCLITool(id: "codex", displayName: "Codex", executableName: "codex", launchCommand: "codex", isInstalled: false, resolvedPath: nil),
        VibeCLITool(id: "opencode", displayName: "OpenCode", executableName: "opencode", launchCommand: "opencode", isInstalled: false, resolvedPath: nil),
        VibeCLITool(id: "droid", displayName: "Droid", executableName: "droid", launchCommand: "droid", isInstalled: false, resolvedPath: nil),
    ]
}
