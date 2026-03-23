# Persistence and State

This document maps persisted state in `idx0`, ownership boundaries, and migration expectations.

## 1. Path Root

Default root:

- `~/Library/Application Support/idx0/`

Resolved via `FileSystemPaths` (`idx0/Utilities/FileSystemPaths.swift`).

## 2. Persisted Files and Owners

### Session and App State

- `sessions.json`
  - Owner: `SessionStore`
  - Payload: `SessionsFilePayload`
- `projects.json`
  - Owner: `ProjectStore`
  - Payload: `ProjectsFilePayload`
- `inbox.json`
  - Owner: `InboxStore`
  - Payload: `InboxFilePayload`
- `settings.json`
  - Owner: `SettingsStore`
  - Payload: `AppSettings`

### Workflow State

- `checkpoints.json` -> `CheckpointStore`
- `handoffs.json` -> `HandoffStore`
- `reviews.json` -> `ReviewStore`
- `approvals.json` -> `ApprovalStore`
- `queue.json` -> `QueueStore`
- `timeline.json` -> `TimelineStore`
- `layout.json` -> `LayoutStore`
- `agent-events.json` -> `AgentEventStore` (handled event IDs, dedupe state)

### Session Runtime Adjacent

- `tile-state.json`
  - Owner: `SessionService` layout persistence layer
  - Stores tabs/panes/Niri layout snapshots per session
- `auto-checkpoints.json`
  - Owner: `AutoCheckpointService`

### Browser Data

Under `~/Library/Application Support/idx0/Browser/`:

- `bookmarks.json`
- `history.json`

## 3. Schema Versions

Current known versions:

- `PersistenceSchema.currentVersion = 3`
- `AppSettings.schemaVersion = 7`
- `TileStatePersistenceSchema.currentVersion = 1`
- Agent event envelope schema: `1`

## 4. Migration and Compatibility Rules

- New fields should decode with defaults when missing.
- Older payloads should be accepted whenever safe.
- Future/unsupported schema versions should avoid destructive overwrite.
- Corrupt payloads should be moved aside and regenerated where possible.

Session/file stores already implement backup strategy using timestamped `*.corrupt.*.json` files.

## 5. Runtime-Only vs Persisted Fields

Persist only durable user/domain state.

Examples of runtime/transient state:

- terminal process runtime states
- live controller references
- stale agent activity snapshots across launches

`SessionService` intentionally clears some runtime-only values (for example agent activity) on restore to avoid stale UI state.

## 6. Tile State Persistence Behavior

Tile-state persistence captures:

- per-session terminal tabs and pane tree
- selected tab
- Niri layout model

Cleanup behavior depends on setting:

- `settings.cleanupOnClose = true` may clear transient state on close/relaunch paths
- otherwise state is restored across relaunch

## 7. Dedupe and Idempotency

Agent event ingestion deduplicates by `eventID`.

- source: `WorkflowService` + `AgentEventStore`
- persisted set prevents replay side effects

## 8. Safe Change Checklist for Persisted Models

Before merging schema/model changes:

- [ ] Added defaulted decoding for new fields.
- [ ] Preserved existing encoded keys unless intentional migration.
- [ ] Added migration/round-trip tests.
- [ ] Updated this doc and any affected protocol docs.
- [ ] Verified app can launch against older local data.

## 9. Quick Inspection Commands

```bash
# Inspect persisted state root
ls -la ~/Library/Application\ Support/idx0

# Pretty-print a state file
cat ~/Library/Application\ Support/idx0/sessions.json | jq

# Find corruption backups
find ~/Library/Application\ Support/idx0 -name '*.corrupt.*.json' | sort
```
