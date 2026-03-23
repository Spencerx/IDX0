# Architecture Map and Ownership Notes

This map reflects the current productionized baseline after full command/contract unification, service decomposition, UI decomposition, and data/test cleanup.

## Layered map

1. App shell (`idx0/App`)
- `idx0App.swift`: menu wiring and app scene composition.
- `AppCoordinator.swift`: slim app orchestration facade.
- `BootstrapCoordinator.swift`: startup path/bootstrap setup.
- `ShortcutCommandDispatcher.swift`: central shortcut/menu/palette command dispatch.
- `IPCServer.swift`: unix socket listener lifecycle.
- `IPCCommandRouter.swift`: IPC request routing into services.

2. Shared contracts (`Sources/IPCShared`)
- `IPCContract.swift`: shared IPC request/response models + command constants.
- Consumed by both app target and CLI target.

3. Session domain (`idx0/Services/Session`, `idx0/Models`)
- `SessionService.swift`: migration facade for session lifecycle/runtime/layout/persistence.
- `SessionService+Lifecycle.swift`: create/relaunch/restore entry points.
- `SessionService+RuntimeLaunch.swift`: runtime controller setup and launch behavior.
- `SessionService+SessionOps.swift`: close/switch/tab-level operations.
- `SessionService+LayoutPersistence.swift`: layout + persistence orchestration.
- `SessionService+NiriCanvasOps.swift`: Niri layout/data mutation surface.
- `SessionService+Utilities.swift`: cross-cutting session utility operations.
- `SessionRestoreCoordinator.swift`: restore metadata + relaunch/restore-state application.
- `SessionStore.swift`, `SettingsStore.swift`: persistence edge.

4. Workflow domain (`idx0/Services/Workflow`, `idx0/Models`)
- `WorkflowService.swift`: workflow facade and high-level coordination.
- `WorkflowService+QueueLayout.swift`: queueing/layout-specific workflow operations.
- `WorkflowService+Collaboration.swift`: review/collaboration transitions.
- `WorkflowService+EventIngestor.swift`: agent event ingestion and queue insertion.
- `AgentEventRouter.swift`: event payload decoding.

5. UI domain (`idx0/UI`)
- `CommandPaletteOverlay.swift`: command surface mapped to shared action dispatch.
- `MainWindow/*`: window composition, overlays, sheets, and chrome extracted into focused files.
- `SessionContainerView.swift`: composition root for session surface.
- `SessionContainerView+*`: focused Niri/classic/browser/snapshot/support slices.
- Session/workflow/settings views consume coordinator/service state.

6. CLI surface (`Sources/idx0`)
- `idx0.swift`: command handlers and request dispatch via shared IPC contract.

## Command surface ownership

Single action source of truth is now represented by:
- `ShortcutActionID` + `ShortcutRegistry` (action identity and bindings)
- `AppCommandRegistry` (command descriptor metadata and surface membership)
- `AppCoordinator.performCommand(_:)` (single execution path)

Surfaces mapped to the same command model:
- App menu
- Keyboard shortcuts
- Command palette
- CLI IPC commands

## Decomposition status

Completed slices:
- Shared IPC contract extraction (`IPCShared`)
- IPC server/router split out of `AppCoordinator`
- Restore behavior extraction (`SessionRestoreCoordinator`)
- Command registry + parity tests
- `AppCoordinator` split with bootstrap + shortcut dispatcher collaborators
- `SessionService` split into lifecycle/runtime/layout/persistence/utilities/Niri collaborators behind facade
- `WorkflowService` split into queue/collaboration/event-ingestion collaborators behind facade
- `SessionContainerView` decomposition into composition root + focused extensions/support views
- Terminal themes moved to resource-backed typed loader with validation tests
- Session service tests split into focused suites (`SessionServiceTests`, `+Launch`, `+Niri`)
- Maintainability gate script + policy docs

Current explicit exception list:
- `VSCodeRuntime` (runtime-heavy integration surface)

## Ownership notes (module-level)

1. App and command surfaces
- Scope: `idx0/App`, `idx0/Keyboard`, `idx0/UI/CommandPaletteOverlay.swift`, `Sources/IPCShared`.
- Responsibilities: command descriptor parity, routing safety, shortcut/menu/palette behavior consistency.

2. Session platform
- Scope: `idx0/Services/Session/*`, `idx0/Persistence/SessionStore.swift`, `idx0/UI/Session`.
- Responsibilities: lifecycle/runtime/layout/persistence migration out of `SessionService` facade.

3. Workflow platform
- Scope: `idx0/Services/Workflow/*`, `idx0/Models/WorkflowModels.swift`, `idx0/UI/Workflow`.
- Responsibilities: queue/review/event ingestion decomposition and transition correctness.

4. Runtime integrations
- Scope: `idx0/Apps/*`, `idx0/Terminal/*`, `idx0/Services/Runtime/*`.
- Responsibilities: external runtime launch/health/retry behavior and platform-specific process concerns.

5. Test platform
- Scope: `idx0Tests/*`.
- Responsibilities: characterization/regression gates and large-suite decomposition into domain suites/builders.

## Governance checkpoints per refactor slice

1. `xcodebuild -scheme idx0 -destination 'platform=macOS' test`
2. `./scripts/maintainability-gate.sh`
3. No intentional behavior changes without explicit bug-fix rationale and tests.
