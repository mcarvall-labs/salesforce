# Salesforce development and delivery

## Promotion flow

| Environment | Alias       | Validation (PR) | Deployment (Merge)     | Test Level                                     |
| ----------- | ----------- | --------------- | ---------------------- | ---------------------------------------------- |
| Development | `AXON_DEV`  | PR to `develop` | Merged PR in `develop` | `RunSpecifiedTests` (fallback `RunLocalTests`) |
| UAT         | `AXON_UAT`  | PR to `uat`     | Merged PR in `uat`     | `RunSpecifiedTests` (fallback `RunLocalTests`) |
| Production  | `AXON_PROD` | PR to `main`    | Merged PR in `main`    | `RunSpecifiedTests` (fallback `RunLocalTests`) |

Create feature/bugfix branches from `develop`.

- Opening a PR against `develop` runs quality checks and validates the delta against `AXON_DEV`.
- Merging into `develop` deploys that same PR's delta to `AXON_DEV`.
- Promoting `develop` to `uat` via PR validates against `AXON_UAT`, and merging deploys to `AXON_UAT`.
- After UAT acceptance, promoting `uat` to `main` via PR validates against `AXON_PROD`, and merging deploys to `AXON_PROD`.

## Workflows and evidence

- `salesforce-ci.yml`: PR creation, reopening and updates targeting develop/uat/main.
  Quality checks plus dry-run delta validation against DEV/UAT/PROD respectively.
- `deploy-salesforce.yml`: push to develop/uat/main, requiring a merged PR associated
  with the exact commit. Direct pushes fail closed. Deploy to DEV/UAT/PROD respectively.

Validation and deployment use `RunSpecifiedTests` for DEV, UAT and PROD alike,
scoped to the Apex test classes actually relevant to the delta, instead of running
every local test class in the org:

- Any test class (`@isTest`) that is itself part of the delta is included automatically.
- Additional coverage can be declared explicitly in the PR description
  ([`.github/PULL_REQUEST_TEMPLATE.md`](../.github/PULL_REQUEST_TEMPLATE.md)) under
  the `### Apex test classes to run` heading, in the fenced code block that follows
  it. List class names separated by spaces and/or commas, e.g.:

  ````
  ### Apex test classes to run

  ```
  FooControllerTest BarTriggerHandlerTest, BazServiceTest
  ```
  ````

  Use this when a changed class or trigger is covered by a test class that isn't
  itself part of this delta.

- If the delta changes a non-test Apex class or trigger and no test class is found
  either in the delta or declared in the PR body, the operation fails closed with a
  message asking for the `### Apex test classes to run` code block — Salesforce
  cannot compute coverage for `RunSpecifiedTests` without an explicit test list.
- If the delta has no Apex/trigger at all (e.g. only LWC, Flow or layout changes),
  the operation falls back to `RunLocalTests` so production code coverage is still
  proven.

PRs never persist metadata. Deployment reruns tests for the actual merged commit
rather than quick-deploying a synthetic PR merge. Authenticated Org IDs are checked
before metadata operations.

Each operation publishes a short PR comment (outcome, commit, baseline, deployment ID,
test counts, initial error) plus a 30-day evidence artifact containing:

- `result.json` — machine-readable outcome, org ID, and full component/test failures.
- `result.html` — human-readable report of the same data, viewable in a browser.
- `delta-package.zip` — the delta re-packaged in mdapi format, i.e. the exact metadata
  submitted to Salesforce for that validation/deployment.
- `source-paths.txt` — the resolved list of changed source-format paths.
- `summary.md` — the same content as the GitHub Actions step summary.

Full component and test failure detail lives only in `result.json`/`result.html`
inside the artifact — it is intentionally not duplicated inline in the PR comment.
Preflight failures may lack a scope file. Runner/setup failures are reported through
job status and logs even if no artifact could be produced. Auth output is never uploaded.
Configuration-only PRs (no `force-app` change) skip `salesforce-validation` entirely —
no checkout, no org contact, no environment/secret access, reported as `Skipped` in
GitHub — and the PR comment says so explicitly instead of embedding a validation
report. Metadata PRs require the appropriate validation environment before
credentials are released.

## GitHub environments

| Environment       | Allowed ref         | Org         |
| ----------------- | ------------------- | ----------- |
| `DEV-VALIDATION`  | `refs/pull/*/merge` | `AXON_DEV`  |
| `DEV`             | `develop`           | `AXON_DEV`  |
| `UAT-VALIDATION`  | `refs/pull/*/merge` | `AXON_UAT`  |
| `UAT`             | `uat`               | `AXON_UAT`  |
| `PROD-VALIDATION` | `refs/pull/*/merge` | `AXON_PROD` |
| `PROD`            | `main`              | `AXON_PROD` |

Configure in each environment:

- Secret `SALESFORCE_AUTH_URL`: target org SFDX auth URL, never committed or logged.
- Variable `SALESFORCE_ORG_ID`: exact expected 18-character Org ID.

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

The delta is always computed directly between the pull request's base branch commit
(from) and the commit being validated or deployed (to) — never from deployment
history. For PR validation, `from` is `github.event.pull_request.base.sha`. For a
post-merge deploy, `from` is the `base.sha` of the merged pull request associated
with the exact deployed commit. `git merge-base --is-ancestor` verifies `from` is a
real ancestor of `to` before diffing, so a bad or stale base fails closed instead of
silently producing a partial delta with missing components. Deploys are serialized
per branch.

Deletions and rename deletions block the delta regardless of baseline source. They
require an explicitly approved destructive release with impact analysis and
recovery planning. Reverts introducing deletions follow the same restriction. Never
silently omit deleted metadata.

Pending/timeout is not success: inspect the Salesforce job before retrying.
A successful deployment with failed comment publication may be redeployed; inspect
post-deploy effects first. Do not overlap manual deploys.
