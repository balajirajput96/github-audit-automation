#!/usr/bin/env bash
set -Eeuo pipefail

out_dir="${1:?output directory is required}"
previous_state="${2:?previous state path is required}"
mkdir -p "$out_dir"
owner="${GITHUB_REPOSITORY_OWNER:-balajirajput96}"
export GH_PAGER=cat GH_FORCE_TTY=0 NO_COLOR=1

repos="$out_dir/repos.tsv"
prs="$out_dir/open-prs.tsv"
runs="$out_dir/recent-runs.tsv"
fails="$out_dir/recent-failures.tsv"
analysis="$out_dir/gemini-analysis.txt"
state="$out_dir/execution-state.json"

printf 'repo\tdefault_branch\tupdated_at\thtml_url\n' > "$repos"
printf 'repo\tpr_number\ttitle\thead_ref\tbase_ref\thead_sha\tdraft\tmergeable_state\tupdated_at\turl\texcluded_jules\n' > "$prs"
printf 'repo\trun_id\tstatus\tconclusion\tcreated_at\tupdated_at\thead_branch\tworkflow\tevent\turl\n' > "$runs"
printf 'repo\trun_id\tstatus\tconclusion\tcreated_at\tupdated_at\thead_branch\tworkflow\tevent\turl\n' > "$fails"

previous_number=$(jq -r '.execution_number // 0' "$previous_state" 2>/dev/null || printf '0')
if ! [[ "$previous_number" =~ ^[0-9]+$ ]]; then previous_number=0; fi

if [ "$previous_number" -ge 2400 ]; then
  printf 'Gemini analysis skipped because the 2,400-run maintenance ceiling has been reached.\n' > "$analysis"
  jq -n \
    --argjson execution_number 2400 \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg repository_owner "$owner" \
    --arg action "hourly_maintenance_run_limit_guard" \
    --arg result "skipped" \
    --arg failure_category "none" \
    --arg recovery_attempt "not_applicable" \
    --arg validation_status "run_limit_guard_written" \
    --arg remaining_blocker "configured_2400_run_limit_reached" \
    --arg next_action "review_or_reconfigure_the_schedule_before_any_additional_maintenance" \
    '{execution_number:$execution_number,timestamp:$timestamp,repository_owner:$repository_owner,action:$action,result:$result,failure_category:$failure_category,recovery_attempt:$recovery_attempt,validation_status:$validation_status,remaining_blocker:$remaining_blocker,next_action:$next_action}' > "$state"
  printf 'execution_number=2400 result=skipped reason=run_limit_reached\n'
  exit 0
fi

execution_number=$((previous_number + 1))

if ! gh api --paginate 'user/repos?per_page=100&affiliation=owner' --jq '.[] | select(.fork == false and .archived == false and .owner.login == "'"$owner"'") | [.name,.default_branch,.updated_at,.html_url] | @tsv' > "$repos.raw"; then
  printf 'Authentication or repository inventory unavailable to this workflow token.\n' > "$out_dir/blocker.txt"
  : > "$repos.raw"
fi
cat "$repos.raw" >> "$repos"

while IFS=$'\t' read -r repo default_branch updated_at html_url; do
  [ -z "$repo" ] && continue
  repo_full="$owner/$repo"
  pulls=$(gh api "repos/$repo_full/pulls?state=open&per_page=100" 2>/dev/null || printf '[]')
  printf '%s' "$pulls" | jq -r --arg repo "$repo" '.[] | [$repo,(.number|tostring),.title,.head.ref,.base.ref,.head.sha,(.draft|tostring),(.mergeable_state//""),.updated_at,.html_url,(if ((.title // "")|test("Jules|Julius|Sentinel";"i")) or ((.head.ref // "")|test("Jules|Julius|Sentinel";"i")) then "true" else "false" end)] | @tsv' >> "$prs"
  workflow_runs=$(gh api "repos/$repo_full/actions/runs?per_page=20" 2>/dev/null || printf '{"workflow_runs":[]}')
  printf '%s' "$workflow_runs" | jq -r --arg repo "$repo" '.workflow_runs[] | [$repo,(.id|tostring),.status,(.conclusion//""),.created_at,.updated_at,(.head_branch//""),(.name//""),(.event//""),.html_url] | @tsv' >> "$runs"
done < <(tail -n +2 "$repos")

tail -n +2 "$runs" | awk -F '\t' 'BEGIN{OFS="\t"} $4=="failure" || $4=="timed_out" || $4=="startup_failure" || ($3!="completed" && $3!="") {print}' >> "$fails"

if [ -n "${GEMINI_API_KEY:-}" ] && [ "$(wc -l < "$fails")" -gt 1 ]; then
  summary=$(awk -F '\t' 'NR>1{print $1 ":" $4}' "$fails" | head -n 30 | tr '\n' ';' | sed 's/"/\\"/g')
  payload=$(jq -n --arg text "Classify these GitHub audit failure rows concisely. Do not suggest credential changes or bypasses. Rows: $summary" '{contents:[{parts:[{text:$text}]}]}')
  gemini_ok=false
  for attempt in 1 2 3; do
    if curl -fsS --max-time 30 -H "x-goog-api-key: $GEMINI_API_KEY" -H 'content-type: application/json' -d "$payload" 'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent' | jq -r '.candidates[0].content.parts[0].text // "Gemini returned no classification."' > "$analysis"; then
      gemini_ok=true
      break
    fi
    sleep $((attempt * 5))
  done
  if [ "$gemini_ok" != true ]; then
    printf 'Gemini analysis failed after bounded retries at the authorized API endpoint; inspect provider/model availability without changing credentials.\n' > "$analysis"
    printf 'Gemini generateContent endpoint unavailable after bounded retries.\n' >> "$out_dir/blocker.txt"
  fi
else
  printf 'Gemini analysis skipped because GEMINI_API_KEY is not configured or no failure rows were present.\n' > "$analysis"
fi

jq -n \
  --argjson execution_number "$execution_number" \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg repository_owner "$owner" \
  --arg action "inventory_active_nonfork_repositories_open_prs_and_recent_workflows" \
  --arg result "completed" \
  --arg failure_category "$(if [ -s "$out_dir/blocker.txt" ]; then printf 'external_or_inventory_blocker'; else printf 'none_or_classified_in_artifacts'; fi)" \
  --arg recovery_attempt "bounded_api_calls_and_secret_safe_artifact_capture" \
  --arg validation_status "inventory_artifacts_written" \
  --arg remaining_blocker "$(if [ -f "$out_dir/blocker.txt" ]; then tr '\n' ' ' < "$out_dir/blocker.txt"; else printf 'none_recorded_by_inventory_runner'; fi)" \
  --arg next_action "inspect_current_failure_rows_and_repair_only_reproducible_issues" \
  '{execution_number:$execution_number,timestamp:$timestamp,repository_owner:$repository_owner,action:$action,result:$result,failure_category:$failure_category,recovery_attempt:$recovery_attempt,validation_status:$validation_status,remaining_blocker:$remaining_blocker,next_action:$next_action}' > "$state"

printf 'execution_number=%s\nrepos=%s\nopen_pr_rows=%s\nrecent_failure_rows=%s\n' "$execution_number" "$(($(wc -l < "$repos")-1))" "$(($(wc -l < "$prs")-1))" "$(($(wc -l < "$fails")-1))"
