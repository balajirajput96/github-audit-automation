#!/usr/bin/env bash
set -Eeuo pipefail

workflow=".github/workflows/hourly-audit.yml"

grep -q '^  actions: write$' "$workflow"
grep -q 'if \[ "$execution_number" -ge 2400 \]; then' "$workflow"
grep -q 'git push origin HEAD:automation-state' "$workflow"
grep -q 'actions/workflows/hourly-audit.yml/disable' "$workflow"

push_line=$(grep -n 'git push origin HEAD:automation-state' "$workflow" | cut -d: -f1)
disable_line=$(grep -n 'actions/workflows/hourly-audit.yml/disable' "$workflow" | cut -d: -f1)
if [ "$disable_line" -le "$push_line" ]; then
  printf 'FAIL: workflow disable must occur after terminal state persistence.\n' >&2
  exit 1
fi

printf 'PASS: 2,400-cycle terminal guard persists state before disabling its own workflow.\n'
