import XCTest
@testable import idx0

final class AgentOutputScannerTests: XCTestCase {
    private let scanner = AgentOutputScanner()

    func testScanDetectsClaudeWorkingFromToolUse() {
        let tail = """
        Claude Code
        read(/tmp/file.swift)
        """

        let result = scanner.scan(newOutput: tail, fullTail: tail, previousResult: nil)

        XCTAssertEqual(result.detectedAgent, .claude)
        XCTAssertEqual(result.state, .working)
        XCTAssertEqual(result.stateDescription, "read(/tmp/file.swift)")
        XCTAssertFalse(result.isApprovalPrompt)
    }

    func testScanDetectsApprovalPromptAndTruncatesContext() {
        let longPrompt = String(repeating: "x", count: 90) + " [y/n]"
        let tail = """
        claude code
        \(longPrompt)
        """

        let result = scanner.scan(newOutput: tail, fullTail: tail, previousResult: nil)

        XCTAssertEqual(result.state, .waitingForInput)
        XCTAssertTrue(result.isApprovalPrompt)
        XCTAssertTrue(result.approvalContext?.hasSuffix("...") == true)
        XCTAssertEqual(result.approvalContext?.count, 80)
    }

    func testScanDetectsErrorLine() {
        let tail = """
        codex openai
        Error: failed to run command
        """

        let result = scanner.scan(newOutput: tail, fullTail: tail, previousResult: nil)

        XCTAssertEqual(result.detectedAgent, .codex)
        XCTAssertEqual(result.state, .error)
        XCTAssertTrue(result.stateDescription?.contains("Error:") == true)
    }

    func testScanDetectsRateLimitAsError() {
        let tail = """
        gemini cli
        API error: rate limit exceeded
        """

        let result = scanner.scan(newOutput: tail, fullTail: tail, previousResult: nil)

        XCTAssertEqual(result.detectedAgent, .gemini)
        XCTAssertEqual(result.state, .error)
        XCTAssertTrue(result.stateDescription?.lowercased().contains("rate limit") == true)
    }

    func testScanDetectsThinkingFromSpinner() {
        let tail = """
        aider>
        ⠋
        """

        let result = scanner.scan(newOutput: tail, fullTail: tail, previousResult: nil)

        XCTAssertEqual(result.detectedAgent, .aider)
        XCTAssertEqual(result.state, .thinking)
        XCTAssertEqual(result.stateDescription, "Thinking...")
    }

    func testScanDetectsThinkingFromKeywordWithCommandLineAgentFallback() {
        let tail = """
        /usr/local/bin/claude --print
        thinking
        """

        let result = scanner.scan(newOutput: tail, fullTail: tail, previousResult: nil)

        XCTAssertEqual(result.detectedAgent, .claude)
        XCTAssertEqual(result.state, .thinking)
    }

    func testScanDetectsCompletionFromShellPromptWhenPreviouslyWorking() {
        let previous = makeResult(agent: .codex, state: .working, description: "Applying patch")
        let tail = """
        codex openai
        gal@mac %
        """

        let result = scanner.scan(newOutput: tail, fullTail: tail, previousResult: previous)

        XCTAssertEqual(result.state, .completed)
        XCTAssertEqual(result.stateDescription, "Finished")
    }

    func testScanDetectsCompletionFromAgentPromptWhenPreviouslyWorking() {
        let previous = makeResult(agent: .claude, state: .working, description: "Working...")
        let tail = """
        claude code
        ❯
        """

        let result = scanner.scan(newOutput: tail, fullTail: tail, previousResult: previous)

        XCTAssertEqual(result.state, .completed)
    }

    func testScanDetectsAiderWorkingKeywords() {
        let tail = """
        aider>
        Editing Sources/App.swift
        """

        let result = scanner.scan(newOutput: tail, fullTail: tail, previousResult: nil)

        XCTAssertEqual(result.detectedAgent, .aider)
        XCTAssertEqual(result.state, .working)
        XCTAssertTrue(result.stateDescription?.contains("Editing") == true)
    }

    func testScanPreservesPreviousActiveStateOnNeutralOutput() {
        let previous = makeResult(agent: .codex, state: .working, description: "Applying patch")
        let tail = """
        codex openai
        done
        """

        let result = scanner.scan(newOutput: "done", fullTail: tail, previousResult: previous)

        XCTAssertEqual(result, previous)
    }

    func testScanKeepsPreviousNonIdleStateWithoutNewOutput() {
        let previous = makeResult(agent: .gemini, state: .thinking, description: "Thinking...")

        let result = scanner.scan(newOutput: "", fullTail: "", previousResult: previous)

        XCTAssertEqual(result, previous)
    }

    func testScanReturnsIdleWithoutSignals() {
        let result = scanner.scan(newOutput: "", fullTail: "", previousResult: nil)
        XCTAssertEqual(result, .idle)
    }

    private func makeResult(agent: AgentType?, state: AgentState, description: String?) -> AgentScanResult {
        AgentScanResult(
            detectedAgent: agent,
            state: state,
            stateDescription: description,
            isApprovalPrompt: false,
            approvalContext: nil
        )
    }
}
