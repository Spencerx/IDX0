import Darwin
import Foundation
import IPCShared

private struct CLIQueueItem: Codable {
    let id: UUID
    let sessionID: UUID
    let category: String
    let title: String
    let subtitle: String?
    let createdAt: Date
    let isResolved: Bool
}

private struct CLIVibeTool: Codable {
    let id: String
    let displayName: String
    let executableName: String
    let launchCommand: String
    let isInstalled: Bool
    let resolvedPath: String?
}

private struct CLIApprovalItem: Codable {
    let id: UUID
    let sessionID: UUID
    let createdAt: Date
    let title: String
    let summary: String
    let requestedAction: String
    let scopeDescription: String?
    let status: String
}

private enum CLIError: Error, LocalizedError {
    case invalidUsage(String)
    case socketPathTooLong
    case connectFailed(String)
    case requestEncodeFailed
    case responseDecodeFailed

    var errorDescription: String? {
        switch self {
        case .invalidUsage(let message):
            return message
        case .socketPathTooLong:
            return "IPC socket path is too long for Unix domain sockets."
        case .connectFailed(let message):
            return message
        case .requestEncodeFailed:
            return "Failed to encode IPC request."
        case .responseDecodeFailed:
            return "Failed to decode IPC response."
        }
    }
}

@main
struct idx0 {
    static func main() {
        do {
            try run()
        } catch {
            fputs("idx0: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        var args = CommandLine.arguments
        _ = args.removeFirst()

        guard let command = args.first else {
            printUsage()
            return
        }

        switch command {
        case "open":
            try handleOpenCommand()

        case "new-session":
            try handleNewSessionCommand(args: Array(args.dropFirst()))

        case "checkpoint":
            try handleCheckpointCommand(args: Array(args.dropFirst()))

        case "handoff":
            try handleHandoffCommand(args: Array(args.dropFirst()))

        case "request-review":
            try handleRequestReviewCommand(args: Array(args.dropFirst()))

        case "focus":
            try handleFocusCommand(args: Array(args.dropFirst()))

        case "queue":
            try handleQueueCommand()

        case "list-approvals":
            try handleListApprovalsCommand(args: Array(args.dropFirst()))

        case "respond-approval":
            try handleRespondApprovalCommand(args: Array(args.dropFirst()))

        case "list-vibe-tools":
            try handleListVibeToolsCommand()

        case "list-sessions":
            try handleListSessionsCommand()

        case "help", "--help", "-h":
            printUsage()

        default:
            throw CLIError.invalidUsage("Unknown command '\(command)'. See `idx0 help`.")
        }
    }

    private static func handleOpenCommand() throws {
        let response = try send(request: IPCRequest(command: IPCCommand.open, payload: [:]))
        try handleStandardResponse(response)
    }

    private static func handleNewSessionCommand(args: [String]) throws {
        let options = parseOptions(args)
        var payload = buildNewSessionPayload(options: options)
        let response: IPCResponse
        if options["default-tool"] != nil {
            response = try send(request: IPCRequest(command: IPCCommand.newSessionWithTool, payload: payload))
        } else if let toolID = options["tool"], !toolID.isEmpty {
            payload["toolID"] = toolID
            response = try send(request: IPCRequest(command: IPCCommand.newSessionWithTool, payload: payload))
        } else {
            response = try send(request: IPCRequest(command: IPCCommand.newSession, payload: payload))
        }
        try handleStandardResponse(response)
    }

    private static func handleCheckpointCommand(args: [String]) throws {
        let options = parseOptions(args)
        guard let session = options["session"], !session.isEmpty else {
            throw CLIError.invalidUsage("checkpoint requires --session <id-or-title>")
        }
        var payload: [String: String] = ["session": session]
        if let title = options["title"], !title.isEmpty { payload["title"] = title }
        if let summary = options["summary"], !summary.isEmpty { payload["summary"] = summary }
        if options["request-review"] != nil { payload["requestReview"] = "true" }
        let response = try send(request: IPCRequest(command: IPCCommand.createCheckpoint, payload: payload))
        try handleStandardResponse(response)
    }

    private static func handleHandoffCommand(args: [String]) throws {
        let options = parseOptions(args)
        guard let session = options["session"], !session.isEmpty else {
            throw CLIError.invalidUsage("handoff requires --session <id-or-title>")
        }
        var payload: [String: String] = ["session": session]
        if let target = options["target"], !target.isEmpty { payload["targetSession"] = target }
        if let checkpointID = options["checkpoint-id"], !checkpointID.isEmpty { payload["checkpointID"] = checkpointID }
        if let title = options["title"], !title.isEmpty { payload["title"] = title }
        if let summary = options["summary"], !summary.isEmpty { payload["summary"] = summary }
        if let risks = options["risks"], !risks.isEmpty { payload["risks"] = risks }
        if let nextActions = options["next-actions"], !nextActions.isEmpty { payload["nextActions"] = nextActions }
        let response = try send(request: IPCRequest(command: IPCCommand.createHandoff, payload: payload))
        try handleStandardResponse(response)
    }

    private static func handleRequestReviewCommand(args: [String]) throws {
        let options = parseOptions(args)
        guard let session = options["session"], !session.isEmpty else {
            throw CLIError.invalidUsage("request-review requires --session <id-or-title>")
        }
        var payload: [String: String] = ["session": session]
        if let checkpointID = options["checkpoint-id"], !checkpointID.isEmpty { payload["checkpointID"] = checkpointID }
        if let summary = options["summary"], !summary.isEmpty { payload["summary"] = summary }
        let response = try send(request: IPCRequest(command: IPCCommand.requestReview, payload: payload))
        try handleStandardResponse(response)
    }

    private static func handleFocusCommand(args: [String]) throws {
        let options = parseOptions(args)
        guard let sessionQuery = options["session"], !sessionQuery.isEmpty else {
            throw CLIError.invalidUsage("focus requires --session <id-or-title>")
        }
        let response = try send(request: IPCRequest(command: IPCCommand.focusSession, payload: ["session": sessionQuery]))
        try handleStandardResponse(response)
    }

    private static func handleQueueCommand() throws {
        let response = try send(request: IPCRequest(command: IPCCommand.listQueue, payload: [:]))
        guard response.success else {
            throw CLIError.connectFailed(response.message ?? "Command failed")
        }
        let queueItems = try decodeJSONArray(CLIQueueItem.self, from: response.data?["json"])
        if queueItems.isEmpty {
            print("Queue empty")
            return
        }
        for item in queueItems {
            let subtitle = item.subtitle ?? ""
            print("[\(item.category)] \(item.title)\t\(item.sessionID.uuidString)\t\(subtitle)")
        }
    }

    private static func handleListApprovalsCommand(args: [String]) throws {
        let options = parseOptions(args)
        var payload: [String: String] = [:]
        if let session = options["session"], !session.isEmpty {
            payload["session"] = session
        }
        if let status = options["status"], !status.isEmpty {
            payload["status"] = status.lowercased()
        }
        let response = try send(request: IPCRequest(command: IPCCommand.listApprovals, payload: payload))
        guard response.success else {
            throw CLIError.connectFailed(response.message ?? "Command failed")
        }
        let approvals = try decodeJSONArray(CLIApprovalItem.self, from: response.data?["json"])
        if approvals.isEmpty {
            print("No approvals")
            return
        }
        for approval in approvals {
            print("[\(approval.status)] \(approval.title)\t\(approval.id.uuidString)\t\(approval.sessionID.uuidString)\t\(approval.summary)")
        }
    }

    private static func handleRespondApprovalCommand(args: [String]) throws {
        let options = parseOptions(args)
        guard let approvalID = options["approval-id"], !approvalID.isEmpty else {
            throw CLIError.invalidUsage("respond-approval requires --approval-id <uuid>")
        }
        guard let statusRaw = options["status"], !statusRaw.isEmpty else {
            throw CLIError.invalidUsage("respond-approval requires --status approved|denied|deferred")
        }
        let status = statusRaw.lowercased()
        guard status == "approved" || status == "denied" || status == "deferred" else {
            throw CLIError.invalidUsage("respond-approval status must be one of: approved, denied, deferred")
        }
        let response = try send(request: IPCRequest(
            command: IPCCommand.respondApproval,
            payload: ["approvalID": approvalID, "status": status]
        ))
        try handleStandardResponse(response)
    }

    private static func handleListVibeToolsCommand() throws {
        let response = try send(request: IPCRequest(command: IPCCommand.listVibeTools, payload: [:]))
        guard response.success else {
            throw CLIError.connectFailed(response.message ?? "Command failed")
        }
        let tools = try decodeJSONArray(CLIVibeTool.self, from: response.data?["json"])
        if tools.isEmpty {
            print("No tools discovered")
            return
        }
        for tool in tools {
            let status = tool.isInstalled ? "installed" : "missing"
            print("\(tool.id)\t\(status)\t\(tool.resolvedPath ?? "-")")
        }
    }

    private static func handleListSessionsCommand() throws {
        let response = try send(request: IPCRequest(command: IPCCommand.listSessions, payload: [:]))
        guard response.success else {
            throw CLIError.connectFailed(response.message ?? "Unknown failure")
        }
        let data = response.data ?? [:]
        let rows = data.map { (id: $0.key, title: $0.value) }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        if rows.isEmpty {
            print("No sessions")
            return
        }
        for row in rows {
            print("\(row.id)\t\(row.title)")
        }
    }

    private static func buildNewSessionPayload(options: [String: String]) -> [String: String] {
        var payload: [String: String] = [:]
        if let title = options["title"], !title.isEmpty {
            payload["title"] = title
        }
        if let repo = options["repo"], !repo.isEmpty {
            payload["repoPath"] = repo
        }
        if let branch = options["branch"], !branch.isEmpty {
            payload["branchName"] = branch
        }
        if let existingWorktree = options["existing-worktree"], !existingWorktree.isEmpty {
            payload["existingWorktreePath"] = existingWorktree
            payload["createWorktree"] = "true"
        }
        if options["worktree"] != nil {
            payload["createWorktree"] = "true"
        }
        return payload
    }

    private static func decodeJSONArray<T: Decodable>(_ type: T.Type, from raw: String?) throws -> [T] {
        guard let raw, !raw.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = raw.data(using: .utf8) else { return [] }
        return try decoder.decode([T].self, from: data)
    }

    private static func handleStandardResponse(_ response: IPCResponse) throws {
        guard response.success else {
            throw CLIError.connectFailed(response.message ?? "Command failed")
        }
        if let message = response.message, !message.isEmpty {
            print(message)
        }
    }

    private static func parseOptions(_ arguments: [String]) -> [String: String] {
        var options: [String: String] = [:]
        var index = 0

        while index < arguments.count {
            let token = arguments[index]
            guard token.hasPrefix("--") else {
                index += 1
                continue
            }

            let key = String(token.dropFirst(2))
            if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                options[key] = arguments[index + 1]
                index += 2
            } else {
                options[key] = "true"
                index += 1
            }
        }
        return options
    }

    private static func send(request: IPCRequest) throws -> IPCResponse {
        let socketURL = try socketURL()
        let path = socketURL.path

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw CLIError.connectFailed("Failed to create IPC socket.")
        }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = Array(path.utf8)
        let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count < maxPathLength else {
            throw CLIError.socketPathTooLong
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            raw.initialize(repeating: 0, count: maxPathLength)
            for index in pathBytes.indices {
                raw[index] = CChar(bitPattern: pathBytes[index])
            }
        }

        let addrLength = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count + 1)
        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, addrLength)
            }
        }

        guard connectResult == 0 else {
            throw CLIError.connectFailed("Could not connect to idx0 (is the app running?).")
        }

        let encoder = JSONEncoder()
        guard let requestData = try? encoder.encode(request) else {
            throw CLIError.requestEncodeFailed
        }

        let wrote = requestData.withUnsafeBytes { bytes in
            write(fd, bytes.baseAddress, bytes.count)
        }
        guard wrote >= 0 else {
            throw CLIError.connectFailed("Failed sending request to idx0.")
        }

        shutdown(fd, SHUT_WR)

        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                responseData.append(contentsOf: buffer.prefix(Int(count)))
                continue
            }
            break
        }

        let decoder = JSONDecoder()
        guard let response = try? decoder.decode(IPCResponse.self, from: responseData) else {
            throw CLIError.responseDecodeFailed
        }
        return response
    }

    private static func socketURL() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CLIError.connectFailed("Unable to resolve Application Support directory.")
        }
        return appSupport
            .appendingPathComponent("idx0", isDirectory: true)
            .appendingPathComponent("run", isDirectory: true)
            .appendingPathComponent("idx0.sock", isDirectory: false)
    }

    private static func printUsage() {
        print(
            """
            idx0 commands:
              idx0 open
              idx0 new-session [--title <title>] [--repo <path>] [--branch <name>] [--worktree] [--existing-worktree <path>] [--tool <tool-id>] [--default-tool]
              idx0 checkpoint --session <id-or-title> [--title <text>] [--summary <text>] [--request-review]
              idx0 handoff --session <id-or-title> [--target <id-or-title>] [--checkpoint-id <uuid>] [--title <text>] [--summary <text>] [--risks a,b] [--next-actions a,b]
              idx0 request-review --session <id-or-title> [--checkpoint-id <uuid>] [--summary <text>]
              idx0 queue
              idx0 list-approvals [--session <id-or-title>] [--status pending|approved|denied|deferred]
              idx0 respond-approval --approval-id <uuid> --status approved|denied|deferred
              idx0 list-vibe-tools
              idx0 focus --session <id-or-title>
              idx0 list-sessions
            """
        )
    }
}
