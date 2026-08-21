# GitHub Audit Automation

This private repository stores the reproducible continuation workflow for the `balajirajput96` GitHub account. The workflow runs hourly through GitHub Actions, inventories active non-fork repositories, reviews open pull requests and recent workflow failures, applies the Jules/Julius exclusion rule, optionally requests a concise Gemini analysis when a repository secret is configured, and persists a machine-readable execution record on the dedicated `automation-state` branch.

The workflow never writes to the default branch, never stores credentials in the repository, and does not merge pull requests. Code repairs and merges remain separate, reviewable pull-request operations. The state branch contains only audit metadata and reports; it must not contain tokens, API keys, passwords, cookies, or private credential values.

## Optional repository secrets

`AUDIT_GH_TOKEN` is optional and is required for cross-repository private-repository inventory from GitHub Actions. Without it, the workflow records an explicit authentication blocker and audits only what the default workflow token can access.

`GEMINI_API_KEY` is optional. When present, the workflow sends only a short redacted summary of counts and failure categories to Gemini for concise classification. When absent, the workflow records that Gemini analysis was skipped; it does not fabricate credentials.

## State model

Each execution increments `execution_number` from 1 through 2,400 and records the UTC timestamp, repository, workflow, exact source commit, toolchain, actions, results, failure categories, recovery attempts, validation status, blockers, and next action. The state is stored on `automation-state`, not `main`, so scheduled persistence does not bypass protected default-branch review. The branch appends a compact JSON-lines `state/execution-index.ndjson` record for every mission cycle, retains the latest `state/execution-state.json` for continuation, and keeps the 24 most recent detailed `state/execution-<number>.json` snapshots for diagnosis.

The workflow is intentionally bounded and idempotent. It reads the previous state before creating the next record, rejects a gap in the compact execution index, avoids duplicating the terminal skipped entry, keeps only current audit artifacts plus the latest state, and never attempts destructive operations or automatic merges.

At cycle 2,400, the runner writes a recoverable no-op record with `result: skipped` and `validation_status: run_limit_guard_written`, persists it on `automation-state`, and then disables this hourly workflow with the narrowly scoped `actions: write` permission. This explicit expiry guard prevents additional inventory work while retaining an auditable terminal state for later review or deliberate reconfiguration.

## Local guard regression check

Run the following command to validate that the 2,400-run guard writes the expected state without calling GitHub or Gemini:

```bash
bash scripts/test_run_limit_guard.sh
bash scripts/test_workflow_ceiling_guard.sh
bash scripts/test_execution_index_guard.sh
```
