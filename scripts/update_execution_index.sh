#!/usr/bin/env bash
set -Eeuo pipefail

state_file="${1:?execution state path is required}"
index_file="${2:?existing index path is required}"
output_file="${3:?output index path is required}"

execution_number="$(jq -er '.execution_number | if type == "number" and floor == . and . >= 1 then . else error("invalid execution_number") end' "$state_file")"
state_result="$(jq -er '.result | strings' "$state_file")"

recovered_index_file=""
cleanup() {
  if [ -n "$recovered_index_file" ]; then
    rm -f "$recovered_index_file"
  fi
}
trap cleanup EXIT

effective_index_file="$index_file"
if [ -f "$index_file" ] && [ -s "$index_file" ]; then
  last_line="$(tail -n 1 "$index_file")"
  if ! printf '%s\n' "$last_line" | jq -e . >/dev/null 2>&1; then
    truncated_number="$(sed -n '$s/.*"execution_number"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$index_file")"
    recovery_file="$(dirname "$index_file")/execution-${truncated_number}.json"
    if [ -z "$truncated_number" ] || [ ! -s "$recovery_file" ] || ! jq -e . "$recovery_file" >/dev/null 2>&1; then
      printf 'Execution index has an unrecoverable malformed trailing record.\n' >&2
      exit 1
    fi
    recovered_index_file="$(mktemp)"
    head -n -1 "$index_file" > "$recovered_index_file"
    jq -c '{execution_number,timestamp,repository,workflow,source_commit,toolchain,action,result,failure_category,recovery_attempt,validation_status,remaining_blocker,next_action}' "$recovery_file" >> "$recovered_index_file"
    effective_index_file="$recovered_index_file"
    printf 'Recovered truncated trailing execution %s from %s.\n' "$truncated_number" "$recovery_file" >&2
  fi
fi

expected_number=1
if [ -f "$effective_index_file" ] && [ -s "$effective_index_file" ]; then
  while IFS= read -r indexed_number; do
    if [ "$indexed_number" != "$expected_number" ]; then
      printf 'Execution index is not contiguous: expected %s, found %s.\n' "$expected_number" "$indexed_number" >&2
      exit 1
    fi
    expected_number=$((expected_number + 1))
  done < <(jq -er '.execution_number | if type == "number" and floor == . and . >= 1 then . else error("invalid indexed execution_number") end' "$effective_index_file")
fi

last_indexed_number=$((expected_number - 1))
should_append=false
if [ "$execution_number" -eq "$expected_number" ]; then
  should_append=true
elif [ "$execution_number" -eq "$last_indexed_number" ] && [ "$state_result" = "skipped" ]; then
  # The 2,400-cycle terminal guard may rewrite the current detailed state, but
  # it must not duplicate the terminal compact-index entry.
  should_append=false
else
  printf 'Execution index continuity violation: expected next %s, received %s.\n' "$expected_number" "$execution_number" >&2
  exit 1
fi

if [ -f "$effective_index_file" ]; then
  cat "$effective_index_file" > "$output_file"
else
  : > "$output_file"
fi

if [ "$should_append" = true ]; then
  jq -c '{execution_number,timestamp,repository,workflow,source_commit,toolchain,action,result,failure_category,recovery_attempt,validation_status,remaining_blocker,next_action}' "$state_file" >> "$output_file"
fi
