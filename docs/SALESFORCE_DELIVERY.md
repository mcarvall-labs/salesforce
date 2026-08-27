# Salesforce development and delivery

## Promotion flow

| Environment | Alias       | Deployment                                     |
| ----------- | ----------- | ---------------------------------------------- |
| Development | `AXON_DEV`  | Developer/Codex during authorized User Stories |
| UAT         | `AXON_UAT`  | Merged PR in `develop`, via delta              |
| Production  | `AXON_PROD` | Merged PR in `main`, via delta                 |

DEV stays empty during pipeline setup. No bootstrap, seed or deploy. User Stories
will introduce required definitions and dependencies incrementally. No pipeline
uses DEV or retired org aliases.

Create Jira issue branches from develop. Obtain owner validation in DEV before
opening the develop PR. After UAT deployment, obtain acceptance before approving
promotion to main. Never merge without authorization.

## Workflows and evidence

- `salesforce-ci.yml`: PR creation, reopening and updates targeting develop/main.
  Quality checks plus dry-run delta validation against UAT/PROD respectively.
- `deploy-salesforce.yml`: push to develop/main, requiring a merged PR associated
  with the exact commit. Direct pushes fail closed. Deploy to UAT/PROD respectively.

Validation and deployment use RunLocalTests. PRs never persist metadata. Deployment
reruns tests for the actual merged commit rather than quick-deploying a different
synthetic PR merge. Authenticated Org IDs are checked before metadata operations.

Each operation publishes a PR comment and a 30-day artifact containing result.json,
source-paths.txt and summary.md. Comments include outcome, commit, baseline,
deployment ID, test counts, initial errors and links to complete evidence.
Preflight failures may lack a scope file. Runner/setup failures are reported through
job status and logs even if no artifact could be produced. Auth output is never uploaded.
Configuration-only PRs report no metadata changes without contacting an org.
They run in the secret-free `CI` environment; metadata PRs require approval of the
appropriate validation environment before credentials are released.

## GitHub environments

| Environment       | Allowed ref         | Org         |
| ----------------- | ------------------- | ----------- |
| `UAT-VALIDATION`  | `refs/pull/*/merge` | `AXON_UAT`  |
| `PROD-VALIDATION` | `refs/pull/*/merge` | `AXON_PROD` |
| `UAT`             | `develop`           | `AXON_UAT`  |
| `PROD`            | `main`              | `AXON_PROD` |

Configure in each environment:

- Secret `SALESFORCE_AUTH_URL`: target org SFDX auth URL, never committed or logged.
- Variable `SALESFORCE_ORG_ID`: exact expected 18-character Org ID.
- Variable `SALESFORCE_BASE_SHA`: full initial commit matching verified installed
  metadata, required until the first successful deployment establishes history.

Require owner approval for both validation environments and PROD. PR workflow code
can access secrets after approval: inspect workflow/script changes first. Fork PRs
are rejected for authenticated validation. No pull_request_target head-code execution.

Protect develop/main: require PRs, current `Lint and unit tests` and
`Validate Salesforce delta` checks, zero required external approvals and resolved
conversations. Block direct pushes, force pushes and deletion, including admins.
Preserve stronger existing protections. Do not bypass checks to install workflows.

This project has a single GitHub user. GitHub does not allow authors to approve
their own PRs, so the owner merges after reviewing the changes and passing checks.
PRs remain mandatory; this does not waive DEV/UAT acceptance or protected
environment approval. Agents still require explicit authorization to merge.

## Baseline, concurrency and recovery

Use the last successful deploy-salesforce.yml push run for the destination branch
(or the verified initial baseline) through the exact operation SHA. Failed runs do
not advance the baseline. Deploys are serialized per branch. Superseded pending
runs remain in the next cumulative delta. PRs use the same deployed baseline.

Do not guess the first baseline from a branch. Audit installed source first. Empty
orgs cannot accept arbitrary increments without dependencies. Missing baselines or
dependencies fail closed; there is no automatic full-org provisioning.
If deployment history expires or is removed, update SALESFORCE_BASE_SHA in both
corresponding environments to the last verified deployment before continuing.

Pending/timeout is not success: inspect the Salesforce job before retrying.
A successful deployment with failed comment publication may be redeployed from the
older baseline; inspect post-deploy effects first. Do not overlap manual deploys.

Deletions and rename deletions block the delta. They require an explicitly approved
destructive release with impact analysis and recovery planning. Reverts introducing
deletions follow the same restriction. Never silently omit deleted metadata.
