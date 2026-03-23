import Foundation

enum ShellIntegrationHealthError: LocalizedError {
    case invalidShellPath(String)
    case unableToResolveShell

    var errorDescription: String? {
        switch self {
        case .invalidShellPath(let path):
            return "Shell not found or not executable at path: \(path)"
        case .unableToResolveShell:
            return "Unable to resolve a usable shell. Set a valid shell path in settings or provide one explicitly."
        }
    }
}

struct ShellIntegrationHealthService {
    func resolvedShell(
        explicitShell: String?,
        preferredShell: String?
    ) throws -> String {
        if let explicitShell = normalize(explicitShell),
           !explicitShell.isEmpty {
            guard isExecutable(path: explicitShell) else {
                throw ShellIntegrationHealthError.invalidShellPath(explicitShell)
            }
            return explicitShell
        }

        if let preferredShell = normalize(preferredShell),
           !preferredShell.isEmpty,
           isExecutable(path: preferredShell) {
            return preferredShell
        }

        if let envShell = normalize(ProcessInfo.processInfo.environment["SHELL"]),
           !envShell.isEmpty,
           isExecutable(path: envShell) {
            return envShell
        }

        if isExecutable(path: "/bin/zsh") {
            return "/bin/zsh"
        }

        throw ShellIntegrationHealthError.unableToResolveShell
    }

    private func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return NSString(string: cleaned).expandingTildeInPath
    }

    private func isExecutable(path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}
