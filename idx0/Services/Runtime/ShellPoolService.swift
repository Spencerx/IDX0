import Foundation

/// Pre-warms expensive resources at app startup so Cmd+N feels instant.
///
/// Caches:
/// - Default shell path resolution
/// - VibeCLI tool discovery (avoids spawning /bin/zsh per tool lookup)
@MainActor
final class ShellPoolService: ObservableObject {
    @Published private(set) var isWarmed = false
    @Published private(set) var cachedShellPath: String?
    @Published private(set) var cachedTools: [VibeCLITool] = []

    private var warmUpTask: Task<Void, Never>?
    private var refreshInFlight = false

    /// Call once at app startup to begin warming in the background.
    func warmUp(preferredShell: String?) {
        guard warmUpTask == nil else { return }
        let preferred = preferredShell
        warmUpTask = Task.detached(priority: .userInitiated) {
            // Create fresh instances to avoid sending @MainActor state across boundaries
            let health = ShellIntegrationHealthService()
            let discovery = VibeCLIDiscoveryService()

            // 1. Resolve default shell (filesystem check, fast but good to cache)
            let shell = try? health.resolvedShell(
                explicitShell: nil,
                preferredShell: preferred
            )

            // 2. Discover installed CLI tools (may spawn /bin/zsh processes — this is the slow part)
            let tools = discovery.discoverInstalledTools()

            await self.applyWarmUpResults(shell: shell, tools: tools)
        }
    }

    private func applyWarmUpResults(shell: String?, tools: [VibeCLITool]) {
        cachedShellPath = shell
        cachedTools = tools
        isWarmed = true
        Logger.info("ShellPoolService warmed: shell=\(shell ?? "nil"), tools=\(tools.filter(\.isInstalled).map(\.id))")
    }

    /// Returns a cached tool by ID, falling back to live discovery if not yet warmed.
    func tool(withID id: String?) -> VibeCLITool? {
        guard let id else { return nil }
        if !isWarmed {
            refreshTools()
        }
        return cachedTools.first(where: { $0.id == id && $0.isInstalled })
    }

    /// Returns all discovered tools (cached if warmed).
    func installedTools() -> [VibeCLITool] {
        if !isWarmed {
            refreshTools()
        }
        return cachedTools.filter(\.isInstalled)
    }

    /// Refresh the tool cache (e.g., after PATH changes or settings update).
    func refreshTools() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        Task.detached(priority: .utility) {
            let tools = VibeCLIDiscoveryService().discoverInstalledTools()
            await self.applyRefreshedTools(tools)
        }
    }

    private func applyCachedTools(_ tools: [VibeCLITool]) {
        cachedTools = tools
    }

    private func applyRefreshedTools(_ tools: [VibeCLITool]) {
        cachedTools = tools
        refreshInFlight = false
    }
}
