import Foundation

enum AgentType: String, Codable, CaseIterable {
    case claude
    case gemini
    case codex
    case opencode
    case aider
    case unknown
}

enum AgentState: String, Codable {
    case idle
    case thinking
    case working
    case waitingForInput
    case completed
    case error
}

struct AgentScanResult: Equatable {
    let detectedAgent: AgentType?
    let state: AgentState
    let stateDescription: String?
    let isApprovalPrompt: Bool
    let approvalContext: String?

    var hasDetectedAgent: Bool {
        guard let detectedAgent else { return false }
        return detectedAgent != .unknown
    }

    static let idle = AgentScanResult(
        detectedAgent: nil,
        state: .idle,
        stateDescription: nil,
        isApprovalPrompt: false,
        approvalContext: nil
    )
}

struct AgentOutputScanner {

    // MARK: - Public

    func scan(newOutput: String, fullTail: String, previousResult: AgentScanResult?) -> AgentScanResult {
        let lines = newOutput.components(separatedBy: .newlines)
        let tailLines = fullTail.components(separatedBy: .newlines).suffix(80)
        let tail = Array(tailLines)

        let agent = detectAgent(lines: tail, previous: previousResult?.detectedAgent)

        // Check approval prompts first (highest priority signal)
        if let approval = detectApprovalPrompt(lines: tail, agent: agent) {
            return AgentScanResult(
                detectedAgent: agent,
                state: .waitingForInput,
                stateDescription: approval.context,
                isApprovalPrompt: true,
                approvalContext: approval.context
            )
        }

        // Check for errors
        if let errorDesc = detectError(lines: tail, agent: agent) {
            return AgentScanResult(
                detectedAgent: agent,
                state: .error,
                stateDescription: errorDesc,
                isApprovalPrompt: false,
                approvalContext: nil
            )
        }

        // Check for completion
        if detectCompleted(lines: tail, newLines: lines, agent: agent, previous: previousResult) {
            return AgentScanResult(
                detectedAgent: agent,
                state: .completed,
                stateDescription: "Finished",
                isApprovalPrompt: false,
                approvalContext: nil
            )
        }

        // Check for active work
        if let workDesc = detectWorking(lines: tail, agent: agent) {
            return AgentScanResult(
                detectedAgent: agent,
                state: .working,
                stateDescription: workDesc,
                isApprovalPrompt: false,
                approvalContext: nil
            )
        }

        // Check for thinking
        if detectThinking(lines: tail, agent: agent) {
            return AgentScanResult(
                detectedAgent: agent,
                state: .thinking,
                stateDescription: "Thinking...",
                isApprovalPrompt: false,
                approvalContext: nil
            )
        }

        // If we had a previous agent detected and there's new output, assume still working
        if let agent, agent != .unknown, !newOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let prev = previousResult?.state ?? .idle
            if prev == .working || prev == .thinking {
                return AgentScanResult(
                    detectedAgent: agent,
                    state: prev,
                    stateDescription: previousResult?.stateDescription,
                    isApprovalPrompt: false,
                    approvalContext: nil
                )
            }
        }

        // Default: keep previous state if we have an agent, otherwise idle
        if let agent, agent != .unknown, let prev = previousResult, prev.state != .idle {
            return prev
        }

        return .idle
    }

    // MARK: - Agent Detection

    private func detectAgent(lines: [String], previous: AgentType?) -> AgentType? {
        let joined = lines.suffix(40).joined(separator: "\n").lowercased()

        // Claude Code patterns
        if joined.contains("claude") && (
            joined.contains("╭") || joined.contains("╰") ||
            joined.contains("tool use") || joined.contains("anthropic") ||
            joined.contains("claude code") || joined.contains("❯")
        ) {
            return .claude
        }

        // Gemini CLI
        if joined.contains("gemini") && (
            joined.contains("generating") || joined.contains("google") ||
            joined.contains("gemini>") || joined.contains("gemini cli")
        ) {
            return .gemini
        }

        // Codex
        if joined.contains("codex") && (
            joined.contains("openai") || joined.contains("sandbox")
        ) {
            return .codex
        }

        // OpenCode
        if joined.contains("opencode") {
            return .opencode
        }

        // Aider
        if joined.contains("aider") && (
            joined.contains("model:") || joined.contains("aider>") || joined.contains("/ask")
        ) {
            return .aider
        }

        // Check for launch commands in recent lines
        for line in lines.suffix(10) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            guard let cmd = parts.first else { continue }
            let cmdName = String(cmd).components(separatedBy: "/").last ?? String(cmd)

            switch cmdName {
            case "claude": return .claude
            case "gemini": return .gemini
            case "codex": return .codex
            case "opencode": return .opencode
            case "aider": return .aider
            default: break
            }
        }

        return previous
    }

    // MARK: - State Detection

    private struct ApprovalInfo {
        let context: String
    }

    private func detectApprovalPrompt(lines: [String], agent: AgentType?) -> ApprovalInfo? {
        let recentLines = lines.suffix(15)

        for line in recentLines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { continue }

            // Claude Code approval patterns
            if trimmed.contains("do you want to") ||
               trimmed.contains("allow") && (trimmed.contains("?") || trimmed.contains("y/n")) ||
               trimmed.contains("proceed?") ||
               trimmed.contains("approve this") {
                return ApprovalInfo(context: extractContext(from: line))
            }

            // Generic approval patterns
            if trimmed.hasSuffix("[y/n]") || trimmed.hasSuffix("[y/n]:") ||
               trimmed.hasSuffix("(yes/no)") || trimmed.hasSuffix("(yes/no):") ||
               trimmed.hasSuffix("[yes/no]") ||
               trimmed.contains("continue? [y") || trimmed.contains("continue? (y") {
                return ApprovalInfo(context: extractContext(from: line))
            }
        }

        return nil
    }

    private func detectError(lines: [String], agent: AgentType?) -> String? {
        let recent = lines.suffix(10)

        for line in recent.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            guard !lower.isEmpty else { continue }

            // Agent-specific error patterns
            if lower.contains("error:") && !lower.contains("error: 0") {
                return String(trimmed.prefix(60))
            }
            if lower.contains("fatal:") || lower.contains("panic:") {
                return String(trimmed.prefix(60))
            }
            if lower.hasPrefix("traceback") || lower.contains("stack trace") {
                return "Error detected"
            }

            // Rate limiting / API errors
            if lower.contains("rate limit") || lower.contains("429") ||
               lower.contains("api error") || lower.contains("authentication failed") {
                return String(trimmed.prefix(60))
            }
        }

        return nil
    }

    private func detectCompleted(lines: [String], newLines: [String], agent: AgentType?, previous: AgentScanResult?) -> Bool {
        // Only consider completion if we were previously in an active state
        guard let prev = previous, prev.state == .working || prev.state == .thinking else {
            return false
        }

        let recent = lines.suffix(5)
        for line in recent {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()

            // Shell prompt returned (agent exited)
            if lower.hasSuffix("$") && lower.count < 80 && lower.count > 0 {
                return true
            }
            if lower.hasSuffix("%") && lower.count < 80 && lower.count > 0 {
                return true
            }

            // Agent-specific input prompts mean the agent finished its turn
            switch agent {
            case .claude:
                if trimmed.hasSuffix("❯") || (trimmed.hasSuffix(">") && trimmed.count < 10) {
                    return true
                }
            case .gemini:
                if trimmed.hasSuffix(">") && trimmed.count < 20 {
                    return true
                }
            case .aider:
                if trimmed.hasSuffix(">") || lower.contains("aider>") {
                    return true
                }
            case .codex:
                if trimmed.hasSuffix(">") && trimmed.count < 15 {
                    return true
                }
            case .opencode:
                if trimmed.hasSuffix(">") && trimmed.count < 15 {
                    return true
                }
            default:
                break
            }
        }

        return false
    }

    private func detectWorking(lines: [String], agent: AgentType?) -> String? {
        let recent = lines.suffix(15)

        switch agent {
        case .claude:
            for line in recent.reversed() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let lower = trimmed.lowercased()

                // Claude Code tool use patterns
                if lower.contains("read(") || lower.contains("edit(") ||
                   lower.contains("write(") || lower.contains("bash(") ||
                   lower.contains("grep(") || lower.contains("glob(") {
                    return String(trimmed.prefix(40))
                }
                if trimmed.hasPrefix("⎿") || trimmed.hasPrefix("│") {
                    return "Working..."
                }
            }

        case .codex:
            for line in recent.reversed() {
                let lower = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if lower.contains("applying") || lower.contains("editing") || lower.contains("writing") {
                    return String(line.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
                }
            }

        case .aider:
            for line in recent.reversed() {
                let lower = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if lower.contains("editing") || lower.contains("applying") ||
                   lower.contains("commit") {
                    return String(line.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
                }
            }

        default:
            break
        }

        return nil
    }

    private func detectThinking(lines: [String], agent: AgentType?) -> Bool {
        let recent = lines.suffix(8)

        for line in recent.reversed() {
            let lower = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !lower.isEmpty else { continue }

            if lower.contains("thinking") || lower.contains("generating") ||
               lower.contains("analyzing") || lower.contains("planning") {
                return true
            }

            // Spinner characters (common in CLI tools)
            if lower.count <= 5 && (lower.contains("⠋") || lower.contains("⠙") ||
               lower.contains("⠹") || lower.contains("⠸") || lower.contains("⠼") ||
               lower.contains("⠴") || lower.contains("⠦") || lower.contains("⠧") ||
               lower.contains("⠇") || lower.contains("⠏")) {
                return true
            }
        }

        return false
    }

    // MARK: - Helpers

    private func extractContext(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 80 {
            return String(trimmed.prefix(77)) + "..."
        }
        return trimmed
    }
}
