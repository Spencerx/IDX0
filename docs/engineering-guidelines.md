# Engineering Guidelines

These rules are production guardrails for maintainability, readability, and low-risk refactors.

## File and Function Size

- Preferred file size: `<= 500 LOC`
- Hard file size cap: `<= 1000 LOC`
- Preferred function size: `<= 80 lines`
- Hard function size cap: `<= 140 lines`
- Exception process:
  - Put approved exceptions in `docs/maintainability-exceptions.txt`
  - Keep exceptions narrow, documented, and periodically revisited

Run the gate locally:

```bash
scripts/maintainability-gate.sh
```

## Dependency Direction

Use this dependency flow and avoid reverse coupling:

1. `Models` and pure value types
2. Services / coordinators / stores
3. View models / app orchestration
4. UI views

Rules:

- UI should not implement business logic directly.
- Cross-cutting behaviors should live in services/coordinators, not view files.
- Prefer protocol-based seams for testability and safe replacement.

## Refactor Safety Rules

For every structural change:

1. Add/keep characterization tests for current behavior.
2. Refactor in small slices with behavior parity checks after each slice.
3. Keep public behavior stable unless an explicit bug fix requires change.
4. Avoid mixing architecture changes and feature work in one patch.

## Command and IPC Consistency

- Reuse shared IPC contract types/constants from `Sources/IPCShared`.
- Route equivalent actions (menu, shortcut, palette) through shared command handlers.
- Add/maintain parity tests when command surfaces are expanded.

## Pragmatic Exceptions

Some files may remain large temporarily during extraction:

- Legacy monolith files under active decomposition
- Data-heavy static mapping files
- Vendor/generated sources

Even in exceptions, prefer new code in small focused units and migrate incrementally.
