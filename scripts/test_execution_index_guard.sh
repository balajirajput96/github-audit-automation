#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

state_file="$temporary_directory/state.json"
index_file="$temporary_directory/index.ndjson"
output_file="$temporary_directory/output.ndjson"

write_state() {
  jq -n --argjson execution_number "$1" --arg result "$2" \
    '{execution_number:$execution_number,timestamp:"2026-08-21T00:00:00Z",repository:"balajirajput96/github-audit-automation",workflow:"hourly-audit.yml",source_commit:"test-commit",toolchain:"test",action:"test",result:$result,failure_category:"none",recovery_attempt:"none",validation_status:"test",remaining_blocker:"none",next_action:"none"}' > "$state_file"
}

write_state 1 completed
"$repository_root/scripts/update_execution_index.sh" "$state_file" "$index_file" "$output_file"
test "$(jq -s 'length' "$output_file")" -eq 1
mv "$output_file" "$index_file"

write_state 3 completed
if "$repository_root/scripts/update_execution_index.sh" "$state_file" "$index_file" "$output_file"; then
  printf 'FAIL: a gap in execution numbering must be rejected.\n' >&2
  exit 1
fi

write_state 2 completed
"$repository_root/scripts/update_execution_index.sh" "$state_file" "$index_file" "$output_file"
test "$(jq -s '.[0].execution_number == 1 and .[1].execution_number == 2' "$output_file")" = true
mv "$output_file" "$index_file"

write_state 2 skipped
"$repository_root/scripts/update_execution_index.sh" "$state_file" "$index_file" "$output_file"
test "$(jq -s 'length' "$output_file")" -eq 2

write_state 3 skipped
cp "$state_file" "$temporary_directory/execution-3.json"
printf '{"execution_number":1}\n{"execution_number":2}\n{"execution_number":3' > "$index_file"
"$repository_root/scripts/update_execution_index.sh" "$state_file" "$index_file" "$output_file"
test "$(jq -s 'length' "$output_file")" -eq 3
test "$(jq -s '.[2].execution_number == 3' "$output_file")" = true
mv "$output_file" "$index_file"

write_state 4 completed
"$repository_root/scripts/update_execution_index.sh" "$state_file" "$index_file" "$output_file"
test "$(jq -s 'length' "$output_file")" -eq 4
test "$(jq -s '.[3].execution_number == 4' "$output_file")" = true

printf 'PASS: execution index rejects gaps, recovers a truncated trailing record, and avoids duplicate terminal guard entries.\n'
