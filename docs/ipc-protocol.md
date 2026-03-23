# idx0 IPC Protocol Reference

This document is the authoritative IPC contract reference for `idx0` as implemented by:

- `idx0/App/IPCServer.swift`
- `idx0/App/IPCCommandRouter.swift`
- `Sources/IPCShared/IPCContract.swift`
- `Sources/idx0/idx0.swift` (CLI client)

## 1. Transport

- Socket type: Unix domain socket (`AF_UNIX`, `SOCK_STREAM`)
- Path: `~/Library/Application Support/idx0/run/idx0.sock`
- Permissions: `0600` (owner only)
- Request model: one JSON request per connection
- Response model: one JSON response, then close

## 2. Request and Response Shapes

Request:

```json
{
  "command": "commandName",
  "payload": {
    "key": "value"
  }
}
```

Response:

```json
{
  "success": true,
  "message": "Human-readable status",
  "data": {
    "key": "value"
  }
}
```

Notes:

- Payload values are strings.
- Boolean-like payload fields are parsed from strings (`1`, `true`, `yes`, `y` for true).
- Some responses return JSON arrays encoded as a string in `data["json"]`.

## 3. Session Resolution Rules

Commands accepting a `session` field resolve in this order:

1. Exact UUID match
2. Case-insensitive exact title match
3. Case-insensitive title substring match (must resolve to exactly one session)

If no or multiple matches are found, command fails.

## 4. Supported Commands

Canonical command constants from `IPCCommand.all`:

- `open`
- `newSession`
- `newSessionWithTool`
- `focusSession`
- `listSessions`
- `createCheckpoint`
- `createHandoff`
- `requestReview`
- `listQueue`
- `listApprovals`
- `respondApproval`
- `listVibeTools`
- `agentEvent`
- `setReviewStatus`
- `markQueueResolved`
- `notify`

## 5. Command Details

### 5.1 `open`

Purpose: Activate/foreground the app.

Payload: none

Success message: `idx0 activated`

### 5.2 `newSession`

Purpose: Request session creation.

Payload fields:

- `title` (optional)
- `repoPath` (optional)
- `branchName` (optional)
- `createWorktree` (optional bool string)
- `existingWorktreePath` (optional)
- `toolID` (optional, explicitly launched after create)

Response is immediate (`Session creation requested`); session creation is async.

### 5.3 `newSessionWithTool`

Purpose: Request session creation and optional default-tool fallback launch.

Payload: same as `newSession`

Behavior:

- if `toolID` provided, that tool is launched
- otherwise default configured tool may auto-launch

### 5.4 `focusSession`

Payload:

- `session` (required, UUID or title query)

Errors:

- missing session
- no match
- ambiguous match

### 5.5 `listSessions`

Payload: none

Data payload:

- map of `sessionUUID -> sessionTitle`

### 5.6 `createCheckpoint`

Payload:

- `session` (required)
- `title` (optional, default `Checkpoint`)
- `summary` (optional, default `Manual checkpoint`)
- `requestReview` (optional bool string)

Response is immediate (`Checkpoint requested`); creation is async.

### 5.7 `createHandoff`

Payload:

- `session` (required source)
- `targetSession` (optional)
- `checkpointID` (optional UUID)
- `title` (optional, default `Handoff`)
- `summary` (optional, default `Handoff requested`)
- `risks` (optional comma-separated list)
- `nextActions` (optional comma-separated list)

### 5.8 `requestReview`

Payload:

- `session` (required source)
- `checkpointID` (optional UUID)
- `summary` (optional, default `Review requested`)

### 5.9 `listQueue`

Payload: none

Data payload:

- `data["json"]` is a JSON array of unresolved `SupervisionQueueItem` values

### 5.10 `listApprovals`

Payload:

- `session` (optional filter)
- `status` (optional filter: `pending|approved|denied|deferred`)

Data payload:

- `data["json"]` is filtered approvals, sorted pending-first then newest-first

### 5.11 `respondApproval`

Payload:

- `approvalID` (required UUID)
- `status` (required: `approved|denied|deferred`)

### 5.12 `listVibeTools`

Payload: none

Data payload:

- `data["json"]` array of `VibeCLITool`

### 5.13 `agentEvent`

Payload:

- `envelope` (required JSON string)

Router behavior:

- decode envelope
- validate schema
- dedupe by `eventID`
- resolve target session
- ingest into workflow queue/timeline/checkpoint/review/handoff/approval flows

### 5.14 `setReviewStatus`

Payload:

- `reviewID` (required UUID)
- `status` (required: `approved|changesRequested|deferred`)

### 5.15 `markQueueResolved`

Payload:

- `queueID` (required UUID)

### 5.16 `notify`

Purpose: create queue/timeline notification and optional session activity transition.

Payload:

- `sessionID` (required UUID)
- `title` (optional, default `Activity`)
- `summary` (optional)
- `category` (optional, defaults to `informational`)
  - supported values: queue categories (`approvalNeeded`, `reviewRequested`, `blocked`, `completed`, `error`, `informational`)
- `activity` (optional: `active|waiting|completed|error|clear`)
- `activityDescription` (optional)

Notes:

- Activity updates are applied only when payload appears agentic (except `clear`, which is always honored).

## 6. Agent Event Envelope Schema

Schema version: `1`

Shape:

```json
{
  "schemaVersion": 1,
  "eventID": "UUID",
  "sessionID": "UUID or null",
  "sessionTitleHint": "string or null",
  "timestamp": "ISO8601",
  "eventType": "progress|checkpoint|handoff|reviewRequest|approvalRequest|completed|blocked|error",
  "payload": {}
}
```

Supported `eventType` values map to `AgentEventType`:

- `progress`
- `checkpoint`
- `handoff`
- `reviewRequest`
- `approvalRequest`
- `completed`
- `blocked`
- `error`

Error semantics:

- unsupported schema -> failure
- duplicate event ID -> failure (`Duplicate event ignored.`)
- unresolved session -> failure
- malformed envelope JSON -> decode failure

Dedup state is persisted in `agent-events.json`.

## 7. CLI Mapping

CLI executable (`Sources/idx0/idx0.swift`) maps to IPC commands:

- `idx0 open` -> `open`
- `idx0 new-session ...` -> `newSession` / `newSessionWithTool`
- `idx0 checkpoint ...` -> `createCheckpoint`
- `idx0 handoff ...` -> `createHandoff`
- `idx0 request-review ...` -> `requestReview`
- `idx0 focus ...` -> `focusSession`
- `idx0 queue` -> `listQueue`
- `idx0 list-approvals ...` -> `listApprovals`
- `idx0 respond-approval ...` -> `respondApproval`
- `idx0 list-vibe-tools` -> `listVibeTools`
- `idx0 list-sessions` -> `listSessions`

## 8. Example Requests

### 8.1 List sessions

```bash
echo '{"command":"listSessions","payload":{}}' \
  | socat - UNIX-CONNECT:"$HOME/Library/Application Support/idx0/run/idx0.sock"
```

### 8.2 Create a repo-backed worktree session

```bash
echo '{
  "command":"newSession",
  "payload":{
    "repoPath":"/Users/me/project",
    "createWorktree":"true",
    "branchName":"idx0/feature-branch"
  }
}' | socat - UNIX-CONNECT:"$HOME/Library/Application Support/idx0/run/idx0.sock"
```

### 8.3 Ingest agent event

```bash
echo '{
  "command":"agentEvent",
  "payload":{
    "envelope":"{\"schemaVersion\":1,\"eventID\":\"0F2F66F2-7C4D-4A96-9C4A-A5F9B4DBA89E\",\"sessionID\":\"11111111-1111-1111-1111-111111111111\",\"sessionTitleHint\":null,\"timestamp\":\"2026-03-22T15:00:00Z\",\"eventType\":\"progress\",\"payload\":{\"summary\":\"running tests\"}}"
  }
}' | socat - UNIX-CONNECT:"$HOME/Library/Application Support/idx0/run/idx0.sock"
```

## 9. Backward Compatibility Expectations

When modifying IPC behavior:

- keep existing command names stable unless a versioned migration is planned
- keep payload parsing tolerant for optional fields
- update `IPCCommand.all`, router handling, CLI mapping, and this doc in one change
