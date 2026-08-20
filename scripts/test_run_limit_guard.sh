#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

printf '{"execution_number":2400}\n' > "$temporary_directory/previous-state.json"
"$repository_root/scripts/run_audit.sh" "$temporary_directory/audit" "$temporary_directory/previous-state.json"

jq -e '
  .execution_number == 2400 and
  .repository == "balajirajput96/github-audit-automation" and
  .workflow == "hourly-audit.yml" and
  .toolchain == "GitHub CLI, GitHub REST API, optional Gemini API" and
  .action == "hourly_maintenance_run_limit_guard" and
  .result == "skipped" and
  .validation_status == "run_limit_guard_written"
' "$temporary_directory/audit/execution-state.json" >/dev/null

test "$(wc -l < "$temporary_directory/audit/repos.tsv")" -eq 1
test "$(wc -l < "$temporary_directory/audit/open-prs.tsv")" -eq 1
test "$(wc -l < "$temporary_directory/audit/recent-runs.tsv")" -eq 1
test "$(wc -l < "$temporary_directory/audit/recent-failures.tsv")" -eq 1

printf 'PASS: 2,400-run guard preserves a recoverable no-op state.\n'
