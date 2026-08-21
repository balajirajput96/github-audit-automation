#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_bin="$tmp_dir/bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ " $* " == *" user/repos?per_page=100&affiliation=owner "* ]]; then
  exit 1
fi
case "$*" in
  *"pulls?state=open&per_page=100"*) printf '[]\n' ;;
  *"actions/runs?per_page=20"*) printf '{"workflow_runs":[]}\n' ;;
  *) printf '[]\n' ;;
esac
FAKE_GH
chmod +x "$fake_bin/gh"

public_payload='[{"name":"public-repo","fork":false,"archived":false,"default_branch":"main","updated_at":"2026-01-01T00:00:00Z","html_url":"https://github.com/example/public-repo","owner":{"login":"test-owner"}}]'
cat > "$fake_bin/curl" <<FAKE_CURL
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' '$public_payload'
FAKE_CURL
chmod +x "$fake_bin/curl"

previous_state="$tmp_dir/previous-state.json"
out_dir="$tmp_dir/out"
printf '{"execution_number":0}\n' > "$previous_state"
PATH="$fake_bin:$PATH" GITHUB_REPOSITORY_OWNER=test-owner \
  bash "$repo_root/scripts/run_audit.sh" "$out_dir" "$previous_state" > "$tmp_dir/run.log"

grep -q '^execution_number=1$' "$tmp_dir/run.log"
grep -q '^repos=1$' "$tmp_dir/run.log"
test "$(wc -l < "$out_dir/repos.tsv")" -eq 2
test ! -e "$out_dir/blocker.txt"
jq -e '.execution_number == 1 and .failure_category == "none_or_classified_in_artifacts"' "$out_dir/execution-state.json" >/dev/null
printf 'PASS: public inventory fallback audits public repositories when user-scoped API is unavailable.\n'
