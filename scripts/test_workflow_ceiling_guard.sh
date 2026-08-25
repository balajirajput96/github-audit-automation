#!/usr/bin/env bash
set -Eeuo pipefail

workflow=".github/workflows/hourly-audit.yml"

grep -q '^  actions: write$' "$workflow"
grep -q 'if \[ "$execution_number" -ge 2400 \]; then' "$workflow"
grep -q 'git push origin HEAD:automation-state' "$workflow"
grep -q 'actions/workflows/hourly-audit.yml/disable' "$workflow"
grep -q 'cp scripts/update_execution_index.sh "\$RUNNER_TEMP/audit/update_execution_index.sh"' "$workflow"
grep -q '"\$RUNNER_TEMP/audit/update_execution_index.sh" "\$RUNNER_TEMP/audit/execution-state.json" "\$index_file" "\$temporary_index"' "$workflow"

push_line=$(grep -n 'git push origin HEAD:automation-state' "$workflow" | cut -d: -f1)
disable_line=$(grep -n 'actions/workflows/hourly-audit.yml/disable' "$workflow" | cut -d: -f1)
helper_copy_line=$(grep -n 'cp scripts/update_execution_index.sh' "$workflow" | cut -d: -f1)
state_switch_line=$(grep -n 'git switch --create automation-state' "$workflow" | cut -d: -f1)
if [ "$disable_line" -le "$push_line" ]; then
  printf 'FAIL: workflow disable must occur after terminal state persistence.\n' >&2
  exit 1
fi

if [ "$helper_copy_line" -ge "$state_switch_line" ]; then
  printf 'FAIL: execution-index helper must be copied before switching to automation-state.\n' >&2
  exit 1
fi

printf 'PASS: helper handoff and 2,400-cycle terminal guard preserve state safely.\n'
