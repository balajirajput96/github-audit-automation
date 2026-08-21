#!/usr/bin/env bash
set -Eeuo pipefail

state_file="${1:?execution state path is required}"
index_file="${2:?existing index path is required}"
output_file="${3:?output index path is required}"

execution_number="$(jq -er '.execution_number | if type == "number" and floor == . and . >= 1 then . else error("invalid execution_number") end' "$state_file")"
state_result="$(jq -er '.result | strings' "$state_file")"

expected_number=1
if [ -f "$index_file" ] && [ -s "$index_file" ]; then
  while IFS= read -r indexed_number; do
    if [ "$indexed_number" != "$expected_number" ]; then
      printf 'Execution index is not contiguous: expected %s, found %s.\n' "$expected_number" "$indexed_number" >&2
      exit 1
    fi
    expected_number=$((expected_number + 1))
  done < <(jq -er '.execution_number | if type == "number" and floor == . and . >= 1 then . else error("invalid indexed execution_number") end' "$index_file")
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

if [ -f "$index_file" ]; then
  cat "$index_file" > "$output_file"
else
  : > "$output_file"
fi

if [ "$should_append" = true ]; then
  jq -c '{execution_number,timestamp,repository,workflow,source_commit,toolchain,action,result,failure_category,recovery_attempt,validation_status,remaining_blocker,next_action}' "$state_file" >> "$output_file"
fi
