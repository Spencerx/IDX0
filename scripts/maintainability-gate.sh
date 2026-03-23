#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

WARN_LOC="${WARN_LOC:-500}"
FAIL_LOC="${FAIL_LOC:-1000}"
FUNC_WARN_LINES="${FUNC_WARN_LINES:-80}"
FUNC_FAIL_LINES="${FUNC_FAIL_LINES:-140}"
EXCEPTIONS_FILE="${EXCEPTIONS_FILE:-docs/maintainability-exceptions.txt}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: ripgrep (rg) is required" >&2
  exit 2
fi

exceptions_norm="$(mktemp)"
trap 'rm -f "$exceptions_norm"' EXIT
if [[ -f "$EXCEPTIONS_FILE" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -z "$line" ]] && continue
    echo "$line" >> "$exceptions_norm"
  done < "$EXCEPTIONS_FILE"
fi

is_exception() {
  local file="$1"
  [[ -s "$exceptions_norm" ]] && grep -Fxq "$file" "$exceptions_norm"
}

SWIFT_FILES=()
while IFS= read -r file; do
  SWIFT_FILES+=("$file")
done < <(rg --files idx0 idx0Tests Sources -g '*.swift' 2>/dev/null | sort)

if [[ ${#SWIFT_FILES[@]} -eq 0 ]]; then
  echo "No Swift files found under idx0/, idx0Tests/, Sources/."
  exit 0
fi

fail_count=0
warn_count=0

echo "== File Length Gate =="
for file in "${SWIFT_FILES[@]}"; do
  loc="$(wc -l < "$file" | tr -d ' ')"
  if is_exception "$file"; then
    if (( loc > FAIL_LOC )); then
      echo "ALLOW  $file:$loc (exception)"
    fi
    continue
  fi

  if (( loc > FAIL_LOC )); then
    echo "FAIL   $file:$loc (> $FAIL_LOC)"
    ((fail_count+=1))
  elif (( loc > WARN_LOC )); then
    echo "WARN   $file:$loc (> $WARN_LOC)"
    ((warn_count+=1))
  fi
done

echo
echo "== Function Length Gate (heuristic) =="

function_report="$(mktemp)"
trap 'rm -f "$function_report" "$exceptions_norm"' EXIT

for file in "${SWIFT_FILES[@]}"; do
  if is_exception "$file"; then
    continue
  fi

  awk -v path="$file" -v warn="$FUNC_WARN_LINES" -v fail="$FUNC_FAIL_LINES" '
    BEGIN {
      in_func = 0
      waiting_for_body = 0
      brace_depth = 0
      func_start = 0
      func_name = ""
      func_lines = 0
    }

    function trim(s) {
      gsub(/^[[:space:]]+/, "", s)
      gsub(/[[:space:]]+$/, "", s)
      return s
    }

    function count_char(s, ch,   i, c) {
      c = 0
      for (i = 1; i <= length(s); i++) {
        if (substr(s, i, 1) == ch) {
          c++
        }
      }
      return c
    }

    function report_current(end_line) {
      if (func_lines > fail) {
        printf("FAIL|%s|%d|%s|%d\n", path, func_start, func_name, func_lines)
      } else if (func_lines > warn) {
        printf("WARN|%s|%d|%s|%d\n", path, func_start, func_name, func_lines)
      }
    }

    {
      line = $0
      line_trim = trim(line)

      if (!in_func) {
        if (line_trim ~ /(^|[[:space:]])func[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/) {
          tmp = line_trim
          sub(/^.*func[[:space:]]+/, "", tmp)
          sub(/<.*/, "", tmp)
          sub(/\(.*/, "", tmp)
          sub(/[[:space:]].*$/, "", tmp)
          func_name = tmp
          func_start = NR
          func_lines = 1
          opens = count_char(line, "{")
          closes = count_char(line, "}")
          brace_depth = opens - closes
          if (opens > 0) {
            in_func = 1
            waiting_for_body = 0
            if (brace_depth <= 0) {
              report_current(NR)
              in_func = 0
              brace_depth = 0
            }
          } else {
            waiting_for_body = 1
          }
          next
        }
      } else {
        func_lines++
        opens = count_char(line, "{")
        closes = count_char(line, "}")
        brace_depth += opens - closes
        if (brace_depth <= 0) {
          report_current(NR)
          in_func = 0
          brace_depth = 0
        }
        next
      }

      if (waiting_for_body) {
        if (line_trim ~ /(^|[[:space:]])func[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/) {
          tmp = line_trim
          sub(/^.*func[[:space:]]+/, "", tmp)
          sub(/<.*/, "", tmp)
          sub(/\(.*/, "", tmp)
          sub(/[[:space:]].*$/, "", tmp)
          func_name = tmp
          func_start = NR
          func_lines = 1
          opens = count_char(line, "{")
          closes = count_char(line, "}")
          brace_depth = opens - closes
          if (opens > 0) {
            in_func = 1
            waiting_for_body = 0
            if (brace_depth <= 0) {
              report_current(NR)
              in_func = 0
              brace_depth = 0
            }
          }
          next
        }

        if (line_trim ~ /^}/) {
          waiting_for_body = 0
          func_lines = 0
          func_name = ""
          next
        }

        func_lines++
        opens = count_char(line, "{")
        closes = count_char(line, "}")
        if (opens > 0) {
          in_func = 1
          waiting_for_body = 0
          brace_depth = opens - closes
          if (brace_depth <= 0) {
            report_current(NR)
            in_func = 0
            brace_depth = 0
          }
        }
      }
    }
  ' "$file" >> "$function_report"
done

if [[ -s "$function_report" ]]; then
  while IFS='|' read -r level file start name lines; do
    printf "%s   %s:%s %s() [%s lines]\n" "$level" "$file" "$start" "$name" "$lines"
    if [[ "$level" == "FAIL" ]]; then
      ((fail_count+=1))
    else
      ((warn_count+=1))
    fi
  done < "$function_report"
fi

echo
echo "Summary: fails=$fail_count warnings=$warn_count"
if (( fail_count > 0 )); then
  exit 1
fi
