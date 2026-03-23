# IDX0

`IDX0` is a native macOS, session-first terminal workspace for agentic development workflows.

It combines fast terminal surfaces (GhosttyKit), session/worktree orchestration, a supervision workflow rail (checkpoints, handoffs, reviews, approvals), and multiple control surfaces (keyboard, menu, command palette, IPC, and CLI).

## What IDX0 Does

- Session-first workflow:
  - Create, focus, pin, and restore multiple long-lived coding sessions.
  - Track per-session state (activity, layout, queue context, metadata).
- Repo/worktree aware launches:
  - Start sessions from repositories, create or attach worktrees, and preserve launch context.
- Multi-surface command model:
  - One action model shared across shortcuts, app menu, command palette, IPC, and CLI.
- Supervision workflow rail:
  - Checkpoints, handoffs, review requests, approval requests, queue items, and timeline events.
- Niri canvas workspace mode:
  - Tiled session surfaces with terminal, browser, and app tiles.
  - Built-in runtime tiles for `t3-code` and `vscode`.
- Embedded browser:
  - Session/browser state, bookmarks/history persistence, and cookie hydration support.
- Tooling orchestration:
  - Discovery and launch of installed agentic CLIs (`gemini-cli`, `claude`, `codex`, `opencode`, `droid`).
- Persistence and recovery:
  - File-backed JSON stores for sessions/workflows/settings with schema-aware compatibility behavior.

## Architecture Snapshot

- App bootstrap/orchestration: `idx0/App`
- Domain services: `idx0/Services`
- Models/contracts: `idx0/Models`
- Persistence stores: `idx0/Persistence`
- Ghostty terminal bridge/surfaces: `idx0/Terminal`
- UI composition: `idx0/UI`
- Shared IPC contract: `Sources/IPCShared`
- CLI client: `Sources/idx0`

## Requirements

- macOS 14+
- Xcode (project currently generated for Xcode 26.3)
- `xcodegen`
- Metal toolchain component:
  - `xcodebuild -downloadComponent MetalToolchain`
- `zig` (only required when building `GhosttyKit.xcframework` from source)

## Quick Start (Source Build)

1. Install prerequisites:

```bash
brew install xcodegen
xcodebuild -downloadComponent MetalToolchain
```

2. Ensure `GhosttyKit.xcframework` is available:

```bash
./scripts/setup.sh
```

Notes:
- If `./GhosttyKit.xcframework` already exists, setup reuses it.
- If it does not exist, setup can build/cache it (and will initialize/clone `ghostty` source as needed).

3. Generate the Xcode project:

```bash
xcodegen generate
```

4. Open and run:

```bash
open idx0.xcodeproj
```

Scheme: `idx0`

## CLI and IPC

`IDX0` includes a local CLI client (`Sources/idx0`) that controls the running app over a Unix domain socket.

Common commands:

```bash
idx0 open
idx0 new-session --title "My Session" --repo /path/to/repo --worktree
idx0 list-sessions
idx0 checkpoint --session "My Session" --title "Before refactor"
idx0 request-review --session "My Session"
idx0 list-approvals
idx0 respond-approval --approval-id <uuid> --status approved
idx0 list-vibe-tools
```

IPC socket path:

- `~/Library/Application Support/idx0/run/idx0.sock`

Protocol reference:

- [`docs/ipc-protocol.md`](/Users/gal/Documents/Github/idx0/docs/ipc-protocol.md)

## Quality Gates

From repo root:

```bash
# Build + tests
xcodebuild -project idx0.xcodeproj -scheme idx0 -destination 'platform=macOS' test

# Maintainability policy gate
./scripts/maintainability-gate.sh

# Core coverage gate (Services/Models/Persistence/Utilities)
./scripts/coverage-core.sh
```

## Documentation

Contributor and architecture docs:

- [`docs/README.md`](/Users/gal/Documents/Github/idx0/docs/README.md)

Recommended reading order for contributors:

1. [`docs/contribution-guide.md`](/Users/gal/Documents/Github/idx0/docs/contribution-guide.md)
2. [`docs/style-guide.md`](/Users/gal/Documents/Github/idx0/docs/style-guide.md)
3. [`docs/testing-guide.md`](/Users/gal/Documents/Github/idx0/docs/testing-guide.md)
4. [`docs/architecture/deep-dive.md`](/Users/gal/Documents/Github/idx0/docs/architecture/deep-dive.md)

## Troubleshooting

- Missing GhosttyKit framework:
  - Run `./scripts/setup.sh` and confirm it ends with `==> Done`.
- Build errors about `metal` tool:
  - Run `xcodebuild -downloadComponent MetalToolchain`.
- CLI tools not appearing in-app:
  - Ensure binaries are on your user shell `PATH`.
  - When running from Xcode, verify scheme environment `PATH` if needed.
- Coverage run fails during local codesign:
  - Use standard build/test + maintainability gate, then run coverage on a signing-valid profile/machine.
