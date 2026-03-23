#!/usr/bin/env bash
set -euo pipefail

THRESHOLD="${CORE_COVERAGE_THRESHOLD:-90}"
PROJECT_PATH="${PROJECT_PATH:-idx0.xcodeproj}"
SCHEME_NAME="${SCHEME_NAME:-idx0}"
DESTINATION="${DESTINATION:-platform=macOS}"
RESULT_BUNDLE="${CORE_COVERAGE_RESULT_BUNDLE:-/tmp/idx0-core-coverage.xcresult}"
TOP_N="${CORE_COVERAGE_TOP_N:-15}"

if [[ -d "$RESULT_BUNDLE" ]]; then
  rm -rf "$RESULT_BUNDLE"
fi

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -destination "$DESTINATION" \
  -enableCodeCoverage YES \
  test \
  -resultBundlePath "$RESULT_BUNDLE" \
  "$@"

coverage_json_path="$(mktemp /tmp/idx0-core-coverage-json.XXXXXX)"
trap 'rm -f "$coverage_json_path"' EXIT
xcrun xccov view --report --json "$RESULT_BUNDLE" > "$coverage_json_path"

python3 - "$THRESHOLD" "$TOP_N" "$coverage_json_path" <<'PY'
import json
import os
import sys

threshold = float(sys.argv[1])
top_n = int(sys.argv[2])
coverage_json_path = sys.argv[3]

with open(coverage_json_path, "r", encoding="utf-8") as handle:
    report = json.load(handle)

target = None
for candidate in report.get("targets", []):
    name = candidate.get("name", "")
    if name == "idx0.app" or name.endswith("/idx0"):
        target = candidate
        break

if target is None:
    print("error: Unable to locate idx0 app target in coverage report.", file=sys.stderr)
    sys.exit(1)

scope_markers = [
    f"{os.sep}idx0{os.sep}Services{os.sep}",
    f"{os.sep}idx0{os.sep}Models{os.sep}",
    f"{os.sep}idx0{os.sep}Persistence{os.sep}",
    f"{os.sep}idx0{os.sep}Utilities{os.sep}",
]

core_files = []
for entry in target.get("files", []):
    path = entry.get("path", "")
    if any(marker in path for marker in scope_markers):
        core_files.append(entry)

if not core_files:
    print("error: No core-scope files matched Services/Models/Persistence/Utilities.", file=sys.stderr)
    sys.exit(1)

covered = sum(file.get("coveredLines", 0) for file in core_files)
executable = sum(file.get("executableLines", 0) for file in core_files)

if executable == 0:
    print("error: Core-scope executable line count is 0.", file=sys.stderr)
    sys.exit(1)

coverage = (covered / executable) * 100.0

print("Core Coverage Report")
print(f"Scope files: {len(core_files)}")
print(f"Covered lines: {covered}")
print(f"Executable lines: {executable}")
print(f"Line coverage: {coverage:.2f}%")

uncovered = []
for file in core_files:
    file_covered = file.get("coveredLines", 0)
    file_exec = file.get("executableLines", 0)
    missing = file_exec - file_covered
    if missing <= 0:
        continue
    file_coverage = (file_covered / file_exec) * 100.0 if file_exec else 0.0
    uncovered.append((missing, file_coverage, file_covered, file_exec, file.get("path", "")))

uncovered.sort(key=lambda row: row[0], reverse=True)

print("")
print(f"Top {min(top_n, len(uncovered))} files by uncovered lines:")
for missing, file_coverage, file_covered, file_exec, path in uncovered[:top_n]:
    rel_path = path
    marker = f"{os.sep}idx0{os.sep}"
    marker_idx = path.rfind(marker)
    if marker_idx >= 0:
        rel_path = path[marker_idx + 1 :]
    print(
        f"- {rel_path}: {file_coverage:.2f}% ({file_covered}/{file_exec}), "
        f"uncovered={missing}"
    )

print("")
if coverage < threshold:
    print(
        f"FAIL: Core coverage {coverage:.2f}% is below threshold {threshold:.2f}%.",
        file=sys.stderr,
    )
    sys.exit(2)

print(f"PASS: Core coverage {coverage:.2f}% meets threshold {threshold:.2f}%.")
PY
