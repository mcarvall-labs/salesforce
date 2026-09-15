<!-- AXF-106-DECISION-20260912 -->
## AXF-106 — current bank and holder decision (2026-09-12)

Developer sequence: inspect production metadata read-only; map consumers and DEV/UAT delta; implement AXF-106 in an isolated worktree; validate security, migration dry run and resume. Coordinate changed installation/cleanup/release slices with AXF-77/78/79; no deploy inferred.

Decision approved by Michel on 2026-09-12; authoritative scope: AXF-106. This active supplement supersedes conflicting bank-reference and onboarding-order assumptions in this document only. It is a requirement change, not evidence of implementation, migration or deployment.

Reuse the Financial Institution object reported in production as the canonical bank directory. Its exact API name/schema and availability in DEV/UAT still require read-only verification. Do not create a duplicate object or infer schema from a label.

Connections select Bank through a Lookup to that directory and a suggested Holder through a Lookup to Account (AXF_Person / AXF_Business). Register/reuse holders before connections; provide inline New holder without losing Item ID or bank selection. Holder registration creates no User and grants no access.

Bank accounts, credit cards, manual-source forms and relevant selectors, filters, reports and integrations consume canonical institution references. Preserve provider connector/institution text and IDs separately. MeuPluggy, name similarity or bank equality never proves bank mapping, source identity or ownership.

Connection holder remains a suggestion. Confirm the holder per account/card through AXF-85 before financial use. Editing connection references must not rewrite confirmed holders, grants, financial facts, allocations or immutable document/archive snapshots.

Display bank and holder names plus masked Item ID; support multiple connections sharing bank/holder, explicit edits, idempotent registration and rediscovery. Existing missing references remain visible pending decisions. An alias-only solution does not satisfy this decision.

Inventory consumers before migration; map only unambiguous associations, report unresolved/conflicting mappings, preserve original values and require repeatable backfill and rollback. Do not delete legacy fields until consumers and parity checks pass. Production mutation and destructive cutover require separate authorization.

Open implementation decisions: verified institution identifiers; mandatory fields/progression gates; inactive/deleted-reference policy; and connections with sources from different banks. Do not impose a blanket required-field retrofit or invent a new automatic mapping rule.

Preserve Dev Done and later work-item history. AXF-106 owns the evolution of delivered AXF-80/84/85/86/88/89/90/91/98. Related open work receives only its applicable compatibility obligations; unrelated reviewed contracts/readiness are not reopened.

Canonical page: https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=3866625

Requirements: https://axon-personal-finances.atlassian.net/browse/AXF-106

<!-- /AXF-106-DECISION-20260912 -->

# Salesforce development and delivery

## Promotion flow

| Environment | Alias       | Validation (PR) | Deployment (Merge)     | Test Level      |
| ----------- | ----------- | --------------- | ---------------------- | --------------- |
| Development | `AXON_DEV`  | PR to `develop` | Merged PR in `develop` | `NoTestRun`     |
| UAT         | `AXON_UAT`  | PR to `uat`     | Merged PR in `uat`     | `RunLocalTests` |
| Production  | `AXON_PROD` | PR to `main`    | Merged PR in `main`    | `RunLocalTests` |

Create feature/bugfix branches from `develop`.

- Opening a PR against `develop` runs quality checks and validates the delta against `AXON_DEV`.
- Merging into `develop` deploys the cumulative delta to `AXON_DEV`.
- Promoting `develop` to `uat` via PR validates against `AXON_UAT`, and merging deploys to `AXON_UAT`.
- After UAT acceptance, promoting `uat` to `main` via PR validates against `AXON_PROD`, and merging deploys to `AXON_PROD`.

## Workflows and evidence

- `salesforce-ci.yml`: PR creation, reopening and updates targeting develop/uat/main.
  Quality checks plus dry-run delta validation against DEV/UAT/PROD respectively.
- `deploy-salesforce.yml`: push to develop/uat/main, requiring a merged PR associated
  with the exact commit. Direct pushes fail closed. Deploy to DEV/UAT/PROD respectively.

Validation and deployment use `NoTestRun` for DEV (per development velocity rules) and
`RunLocalTests` for UAT and PROD. PRs never persist metadata. Deployment reruns tests
for the actual merged commit rather than quick-deploying a synthetic PR merge.
Authenticated Org IDs are checked before metadata operations.

Each operation publishes a PR comment and a 30-day artifact containing result.json,
source-paths.txt and summary.md. Comments include outcome, commit, baseline,
deployment ID, test counts, initial errors and links to complete evidence.
Preflight failures may lack a scope file. Runner/setup failures are reported through
job status and logs even if no artifact could be produced. Auth output is never uploaded.
Configuration-only PRs report no metadata changes without contacting an org.
They run in the secret-free `CI` environment; metadata PRs require the appropriate
validation environment before credentials are released.

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
