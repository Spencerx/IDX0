import Foundation
import UserNotifications

@MainActor
final class TerminalMonitorService: ObservableObject {
    struct SessionMonitorState {
        var lastSnapshotTail: String = ""
        var lastScanResult: AgentScanResult = .idle
        var lastPollTime: Date = .distantPast
        var hasActivity: Bool = false
    }

    @Published private(set) var agentStates: [UUID: AgentScanResult] = [:]

    private var states: [UUID: SessionMonitorState] = [:]
    private let scanner = AgentOutputScanner()
    private var pollTimer: Timer?
    private let tailLineCount = 200

    private weak var host: GhosttyAppHost?
    private var sessionSurfaceProvider: ((UUID) -> GhosttyTerminalSurface?)?
    private var sessionInfoProvider: ((UUID) -> (title: String, isFocused: Bool)?)?

    // Notification debouncing
    private var lastNotificationSentAt: [UUID: Date] = [:]
    private let notificationDebounceInterval: TimeInterval = 30

    // Callbacks
    var onAgentStarted: ((UUID) -> Void)?
    var onStateChanged: ((UUID, AgentScanResult) -> Void)?

    func configure(
        host: GhosttyAppHost,
        surfaceProvider: @escaping (UUID) -> GhosttyTerminalSurface?,
        sessionInfoProvider: @escaping (UUID) -> (title: String, isFocused: Bool)?
    ) {
        self.host = host
        self.sessionSurfaceProvider = surfaceProvider
        self.sessionInfoProvider = sessionInfoProvider
    }

    func startMonitoring() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollAllSessions()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func trackSession(_ sessionID: UUID) {
        if states[sessionID] == nil {
            states[sessionID] = SessionMonitorState()
        }
    }

    func untrackSession(_ sessionID: UUID) {
        states.removeValue(forKey: sessionID)
        agentStates.removeValue(forKey: sessionID)
    }

    func notifyActivity(for sessionID: UUID) {
        states[sessionID]?.hasActivity = true
    }

    // MARK: - Polling

    private func pollAllSessions() {
        let sessionIDs = Array(states.keys)
        for sessionID in sessionIDs {
            pollSession(sessionID)
        }
    }

    private func pollSession(_ sessionID: UUID) {
        guard var state = states[sessionID] else { return }
        guard let surface = sessionSurfaceProvider?(sessionID) else { return }
        guard let host else { return }

        guard let fullText = host.dumpScrollback(surface) else { return }

        // Extract tail for diffing
        let allLines = fullText.components(separatedBy: .newlines)
        let tailLines = Array(allLines.suffix(tailLineCount))
        let currentTail = tailLines.joined(separator: "\n")

        // Compute new output since last poll
        let newOutput: String
        if state.lastSnapshotTail.isEmpty {
            newOutput = currentTail
        } else {
            newOutput = computeNewOutput(previous: state.lastSnapshotTail, current: currentTail)
        }

        // Skip if no new output
        guard !newOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.hasActivity else {
            state.lastPollTime = Date()
            states[sessionID] = state
            return
        }

        let previousResult = state.lastScanResult
        let result = scanner.scan(
            newOutput: newOutput,
            fullTail: currentTail,
            previousResult: previousResult
        )

        state.lastSnapshotTail = currentTail
        state.lastScanResult = result
        state.lastPollTime = Date()
        state.hasActivity = false
        states[sessionID] = state

        // Detect transitions
        let stateChanged = result.state != previousResult.state
            || result.isApprovalPrompt != previousResult.isApprovalPrompt

        if stateChanged {
            agentStates[sessionID] = result
            onStateChanged?(sessionID, result)

            // Detect agent start (idle/completed → thinking/working)
            if (previousResult.state == .idle || previousResult.state == .completed)
                && (result.state == .thinking || result.state == .working) {
                onAgentStarted?(sessionID)
            }

            // Send macOS notification for background sessions needing attention or finished
            if result.hasDetectedAgent
                && (result.state == .waitingForInput || result.state == .error || result.state == .completed) {
                sendNotificationIfNeeded(sessionID: sessionID, result: result)
            }
        } else if agentStates[sessionID] != result {
            agentStates[sessionID] = result
        }
    }

    private func computeNewOutput(previous: String, current: String) -> String {
        // Find where previous tail ends in current
        // Use last few lines of previous as anchor
        let prevLines = previous.components(separatedBy: .newlines)
        let anchorCount = min(3, prevLines.count)
        let anchor = prevLines.suffix(anchorCount).joined(separator: "\n")

        if let range = current.range(of: anchor, options: .backwards) {
            let after = current[range.upperBound...]
            return String(after)
        }

        // If anchor not found, treat everything as new
        return current
    }

    // MARK: - macOS Notifications

    private func sendNotificationIfNeeded(sessionID: UUID, result: AgentScanResult) {
        guard let info = sessionInfoProvider?(sessionID) else { return }

        // Don't notify for the focused session
        guard !info.isFocused else { return }

        // Debounce
        if let lastSent = lastNotificationSentAt[sessionID],
           Date().timeIntervalSince(lastSent) < notificationDebounceInterval {
            return
        }

        lastNotificationSentAt[sessionID] = Date()

        let content = UNMutableNotificationContent()
        content.title = info.title
        content.sound = .default

        switch result.state {
        case .waitingForInput:
            if result.isApprovalPrompt {
                content.body = result.approvalContext ?? "Needs approval"
            } else {
                content.body = "Waiting for input"
            }
        case .error:
            content.body = result.stateDescription ?? "Error occurred"
        case .completed:
            content.body = result.stateDescription ?? "Agent finished"
        default:
            return
        }

        content.userInfo = ["sessionID": sessionID.uuidString]

        let request = UNNotificationRequest(
            identifier: "idx0.session.\(sessionID.uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Query

    func sessionsNeedingAttention() -> Int {
        agentStates.values.filter { state in
            state.hasDetectedAgent && (state.state == .waitingForInput || state.state == .error)
        }.count
    }

    func approvalResult(for sessionID: UUID) -> AgentScanResult? {
        guard let result = agentStates[sessionID], result.hasDetectedAgent, result.isApprovalPrompt else { return nil }
        return result
    }
}
