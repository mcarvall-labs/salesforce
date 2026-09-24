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

Each operation publishes a compact, visual PR comment — a ✅/❌/⚪ status heading, a
small table (deployment ID, component count, tests completed/failed, commit), the
error message when failed, and a direct link to download the evidence artifact
(`.../actions/runs/{run}/artifacts/{id}`, opens the zip download for anyone with repo
read access already signed in) plus a link to the full run logs — alongside a 30-day
evidence artifact containing:

- `result.json` — machine-readable outcome, org ID, and full component/test failures.
- `result.html` — human-readable report of the same data, viewable in a browser.
- `delta-package.zip` — the delta re-packaged in mdapi format, i.e. the exact metadata
  submitted to Salesforce for that validation/deployment.
- `source-paths.txt` — the resolved list of changed source-format paths.
- `summary.md` — the same content as the GitHub Actions step summary.
- `destructiveChanges.xml` + `package.xml` — present only when the delta deletes
  force-app files; the ready-to-review manifest for a manual destructive deploy
  (never applied automatically). See below.

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

Deleted files (and rename deletions, seen as delete+add) never enter the
add/modify delta and are never auto-deployed by either `salesforce-ci.yml` or
`deploy-salesforce.yml` — that still requires an explicitly approved destructive
release with impact analysis and recovery planning, applied as a separate manual
step. To remove that toil, the pipeline auto-generates the manifest for that
release: whenever a PR/push deletes force-app files, `salesforce-delivery.mjs`
maps each deleted path to its Salesforce metadata type/member (`ApexClass`,
`CustomField`, `CustomObject`, `PermissionSet`, etc. — see
`TOP_LEVEL_DESTRUCTIVE_TYPES`/`OBJECT_CHILD_DESTRUCTIVE_TYPES` in the script) and
writes `destructiveChanges.xml` + an empty companion `package.xml` into the
evidence artifact. The PR/deploy comment flags this explicitly
("⚠️ N deletion(s) detected — NOT auto-deployed"). Any change unresolvable to a
known type — notably LWC/Aura bundle deletions, where a partial-bundle deletion
(some files removed, component not fully deleted) can't be told apart from a full
component removal by path alone — is listed as unresolved and needs fully manual
triage; never guessed at. Reverts introducing deletions follow the same path.
Never silently omit deleted metadata.

If the delta has both additions/modifications and deletions, the former still
validates/deploys normally; only the deletions are set aside. If a change is
_only_ deletions, the operation stops with outcome "Destructive changes only —
manual review required" (not a failure) without contacting the org, since there
is nothing safe to auto-validate/deploy.

### Versioned destructive manifests (actually applied)

`manifest/destructiveChangesPre.xml` and `manifest/destructiveChangesPost.xml`
(see `manifest/README.md`) are a different, opt-in mechanism from the
auto-generated evidence above: when either has `<types>` entries, they are
passed straight to `sf project deploy start --pre-destructive-changes` /
`--post-destructive-changes` — genuinely applied, on every validate (dry-run)
and deploy, in every environment the file reaches as it's promoted
`develop` → `uat` → `main`. Committing a non-empty manifest via a reviewed PR
_is_ the explicitly approved destructive release; there's no separate
off-pipeline step for that case. Empty it again in a follow-up commit once
applied where intended, or it keeps re-submitting the same request on every
future deploy. Managed package (`namespace__`-prefixed) components can't be
removed this way — Salesforce rejects it.

Use this specifically for a one-time reconciliation of metadata that predates
the current git history (e.g. an org has components no branch ever tracked) —
not as the default path for ordinary feature-driven deletions, which the
auto-generated `destructiveChanges.xml` already covers with a lighter-weight,
off-pipeline manual step. Verify org identity and impact before adding
anything here; this is deploying deletions for real.

**Tracking is mandatory, not optional.** A candidate for this kind of legacy
cleanup must never live only in chat history or a PR comment — record it in
[`docs/destructive-backlog.md`](destructive-backlog.md) (status, impact
analysis, exclusions and why) and file/update a Jira ticket under `AXF` (see
[AXF-161](https://axon-personal-finances.atlassian.net/browse/AXF-161) for the
current one) before ending the task. Whoever eventually applies an entry
re-verifies it against the live org first — the backlog is a snapshot, not a
guarantee it still holds.

A checked-in manifest's presence alone is enough to trigger a deploy, even
for a commit whose own `force-app` diff is empty — e.g. the PR that adds
`manifest/destructiveChangesPost.xml` only touches `manifest/`, but its
deploy to DEV still runs and applies it. It isn't silently skipped as "no
metadata changes."

`sf project deploy start --pre/post-destructive-changes` rejects
`--source-dir`/`--metadata-dir`; it requires `--manifest <package.xml>`
instead (file paths resolve from the project's own source dirs regardless of
where that package.xml physically sits, so the mdapi-converted one already
built for `delta-package.zip` is reused as-is; a fresh empty one is written
for a pure-destructive deploy with no additive delta). `--ignore-warnings` is
always added alongside it, so deleting a component that doesn't exist in the
target environment — expected wherever that legacy metadata was never
deployed, e.g. DEV/UAT — doesn't fail the whole run; Salesforce only reports
it as a warning, not an error.

Pending/timeout is not success: inspect the Salesforce job before retrying.
A successful deployment with failed comment publication may be redeployed; inspect
post-deploy effects first. Do not overlap manual deploys.
