# Style Guide

This style guide captures conventions already used across the `idx0` codebase.

## 1. Architectural Style

### 1.1 Layering Rule

Use this dependency direction:

1. Models/value types (`idx0/Models`)
2. Stores/services/coordinators (`idx0/Services`, `idx0/Persistence`)
3. App orchestration (`idx0/App`)
4. UI (`idx0/UI`)

Avoid reverse coupling (for example, model code depending on SwiftUI view types).

### 1.2 Decomposition Pattern

Large domains use extension slices on facades:

- `SessionService+Lifecycle.swift`
- `SessionService+RuntimeLaunch.swift`
- `SessionService+SessionOps.swift`
- `SessionService+LayoutPersistence.swift`
- `SessionService+NiriCanvasOps.swift`
- `SessionService+Utilities.swift`
- `WorkflowService+QueueLayout.swift`
- `WorkflowService+Collaboration.swift`
- `WorkflowService+EventIngestor.swift`

When adding behavior, prefer existing concern slices before creating a new top-level type.

## 2. Swift Conventions

### 2.1 Naming

- Types: `UpperCamelCase`
- Functions/properties/locals: `lowerCamelCase`
- Enum cases: concise, behavior-centric (for example `approvalNeeded`, `restoreMetadataOnly`)
- Action IDs: verb-driven, surface-agnostic (for example `focusNextSession`, `toggleFocusMode`)

### 2.2 Access and Mutability

- Use `private(set)` for published read-mostly state.
- Prefer `let` unless mutation is required.
- Keep derived state computed where possible instead of duplicated storage.

### 2.3 Error Handling

- Define domain errors using `LocalizedError` with user-facing descriptions.
- Return structured failures instead of `fatalError` except startup-critical app boot failures.
- Log operational failures through `Logger` (`com.gal.idx0`) with enough context to triage.

## 3. Concurrency and Actor Discipline

- UI/orchestration types are generally `@MainActor` (`AppCoordinator`, `SessionService`, `WorkflowService`).
- Keep non-UI long work in background tasks and report state back to main actor.
- Use `nonisolated(unsafe)` sparingly and only when needed for external protocol boundaries or captured dependencies.
- Do not block main actor with process or file heavy work.

## 4. State and Persistence Patterns

- Persisted payloads should include schema version where applicable.
- Decode with defaults to preserve backward compatibility.
- Corrupt file strategy should prefer backup + reset over crash.
- Writes should be atomic.
- Runtime-only fields should be cleared on restore when stale state is dangerous (for example `agentActivity`).

## 5. Command-Surface Consistency Rules

Any new command-like behavior must satisfy:

- Unique `ShortcutActionID`
- Shortcut registry entry (if remappable/actionable)
- Dispatcher handling path
- Command palette discoverability (unless intentionally hidden)
- Menu parity as applicable
- IPC parity when behavior is expected from automation/CLI

Add/update parity tests (`AppCommandRegistryTests`, shortcut tests, IPC tests).

## 6. UI Style and Composition

- Keep root views compositional; move behavior into focused helper extensions/files.
- Prefer small, purpose-specific view files over giant monolith views.
- Keep heavy business logic out of view bodies.
- Derive UI from service state; avoid hidden parallel state machines in views.

## 7. Runtime Integration Style

- Treat Ghostty bridge code and runtime launch wrappers as critical infrastructure.
- Favor defensive fallback behavior over hard failure (for example degraded mode with clear status text).
- Keep shell/runtime assumptions explicit and logged.

## 8. Script Style

Shell scripts under `scripts/` should:

- Start with `set -euo pipefail`.
- Validate required tools up front.
- Emit concise, actionable failure messages.
- Avoid destructive behavior unless explicitly intended.

## 9. Maintainability Targets

Current policy:

- Preferred file size: `<= 500 LOC`
- Hard file cap: `<= 1000 LOC`
- Preferred function size: `<= 80 lines`
- Hard function cap: `<= 140 lines`

Run: `./scripts/maintainability-gate.sh`

If exceptions are needed, document in `docs/maintainability-exceptions.txt` with narrow scope.
