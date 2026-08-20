# GitHub Audit Automation

This private repository stores the reproducible continuation workflow for the `balajirajput96` GitHub account. The workflow runs hourly through GitHub Actions, inventories active non-fork repositories, reviews open pull requests and recent workflow failures, applies the Jules/Julius exclusion rule, optionally requests a concise Gemini analysis when a repository secret is configured, and persists a machine-readable execution record on the dedicated `automation-state` branch.

The workflow never writes to the default branch, never stores credentials in the repository, and does not merge pull requests. Code repairs and merges remain separate, reviewable pull-request operations. The state branch contains only audit metadata and reports; it must not contain tokens, API keys, passwords, cookies, or private credential values.

## Optional repository secrets

`AUDIT_GH_TOKEN` is optional and is required for cross-repository private-repository inventory from GitHub Actions. Without it, the workflow records an explicit authentication blocker and audits only what the default workflow token can access.

`GEMINI_API_KEY` is optional. When present, the workflow sends only a short redacted summary of counts and failure categories to Gemini for concise classification. When absent, the workflow records that Gemini analysis was skipped; it does not fabricate credentials.

## State model

Each execution increments `execution_number` from 1 through 2,400 and records the UTC timestamp, repository/workflow actions, results, failure categories, recovery attempts, validation status, blockers, and next action. The state is stored on `automation-state`, not `main`, so scheduled persistence does not bypass protected default-branch review.

The workflow is intentionally bounded and idempotent. It reads the previous state before creating the next record, keeps only current audit artifacts plus the latest state, and never attempts destructive operations or automatic merges.
