# Core Coverage Policy

This repository uses a core-logic line-coverage gate focused on non-UI code.

## Scope

The core coverage gate includes only files under:

- `idx0/Services/**`
- `idx0/Models/**`
- `idx0/Persistence/**`
- `idx0/Utilities/**`

Everything else (for example `idx0/UI/**`) is excluded from this threshold.

## Command

Run the coverage gate script from the repository root:

```bash
scripts/coverage-core.sh
```

The script runs `xcodebuild` with code coverage enabled, parses the `xccov` report, and prints:

- total covered and executable lines for the core scope
- aggregate core line coverage percentage
- the top uncovered core files by uncovered-line count

## Threshold

Default threshold is `90%` core line coverage.

You can override the threshold for exploratory runs:

```bash
CORE_COVERAGE_THRESHOLD=85 scripts/coverage-core.sh
```

If coverage is below the configured threshold, the script exits non-zero and prints a failure message.
