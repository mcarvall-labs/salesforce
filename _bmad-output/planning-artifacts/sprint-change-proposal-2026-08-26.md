---
title: "Sprint Change Proposal: AXON_DEV Rejection Rollback"
status: approved
created: 2026-08-26
approved: 2026-08-26
language: en
---

# Sprint Change Proposal: AXON_DEV Rejection Rollback

## 1. Issue Summary

Salesforce pull requests are validated against `AXON_DEV` without persistence. After an issue is merged into `develop`, the immutable integration commit is deployed persistently to `AXON_DEV` for integrated sandbox acceptance. The delivery rules state that a rejected issue must be reverted in `develop`, but the repository does not currently define or automate a complete rollback procedure.

The current delta script processes added, copied, modified, and renamed files (`ACMR`) and intentionally excludes deleted metadata. Consequently, reverting an issue that originally added Salesforce metadata removes the source from Git but does not remove the deployed component from `AXON_DEV`. A Git revert alone therefore does not prove that Git, the sandbox, and Jira have been reconciled.

The change was identified while reviewing the timing of the development deployment and the expected sandbox approval process. The existing post-merge deployment timing remains unchanged.

## 2. Impact Analysis

### Epic and story impact

- Existing product epics remain viable and require no scope or sequencing changes.
- No functional User Story acceptance criteria need to be rewritten.
- A dedicated Jira Task should track implementation of the delivery controls and evidence.
- Any future issue that mutates data, adds metadata, deletes metadata, or changes irreversible org configuration must include a rollback classification before merge.

### Product requirements impact

No PRD change is required. The proposal operationalizes requirements that already exist:

- NFR-10 protects the baseline through compatibility, migration, regression assessment, and rollback risk analysis.
- NFR-15 establishes recovery expectations.
- NFR-21 requires versioned releases, drift reconciliation, and rollback that does not destroy facts or reuse identities.

### Architecture impact

The approved architecture already requires auditable release gates, recovery evidence, rollback watermarks, and non-destructive treatment of business facts. The change adds repository delivery controls without redefining domain architecture.

### UX impact

No end-user UX change is required.

### Technical and operational impact

The following artifacts require implementation changes:

- `.ai/DELIVERY_RULES.md`
- `.ai/GITHUB.md`
- `.github/pull_request_template.md` (new)
- `.github/workflows/rollback-development.yml` (new)
- `scripts/ci/build-salesforce-rollback.sh` (new)
- `scripts/ci/check-rollback-conflicts.sh` (new)
- `scripts/ci/validate-salesforce-manifest.sh` (new)

The existing development deployment and PR validation trigger model remains unchanged.

## 3. Recommended Approach

### Selected path

Use a direct process adjustment with a reviewed forward revert and a dedicated rollback deployment. Never restore the shared sandbox by deploying an arbitrary older branch or commit.

### Rationale

A reviewed revert preserves protected-branch history and provides an auditable corrective commit. A dedicated rollback workflow is still required because the normal delta workflow excludes deleted files. Separating the workflows prevents ordinary deployments from acquiring broad destructive capability.

### Alternatives considered

1. **Deploy an older issue branch to the sandbox:** rejected because it can overwrite later integrated work and creates untracked drift.
2. **Extend every normal deployment to process deletions:** rejected because it broadens destructive authority for all merges and conflicts with the existing explicit-authorization policy.
3. **Perform all rollback steps manually:** rejected because the procedure would be difficult to reproduce, validate, and audit.
4. **Trigger rollback directly from Jira:** deferred until authentication, idempotency, and cross-system failure handling are designed and proven.

### Scope classification

**Moderate.** The product backlog does not require reorganization, but the implementation spans protected-branch policy, GitHub Actions, Salesforce Metadata API manifests, Jira evidence, and destructive-operation approval.

### Effort and risk

- Estimated implementation effort: medium.
- Technical risk: medium.
- Product timeline impact: low, unless existing issues contain data migrations or irreversible org changes without compensating procedures.
- Primary failure modes: deleting a component that belongs to a later change, incomplete rollback of data mutations, stale deployment SHA selection, unsupported metadata type mapping, and false completion after Git revert only.

## 4. Detailed Change Proposals

### 4.1 Delivery policy

**Artifact:** `.ai/DELIVERY_RULES.md`  
**Section:** Validation and deployment

**Current:**

```markdown
- If integrated validation rejects an issue, revert it in `develop`; never overwrite DEV with an older issue branch.
```

**Proposed:**

```markdown
- If integrated validation rejects an issue, rollback must be performed through a reviewed revert commit in `develop`; never overwrite DEV with an older issue branch.
- Before creating the revert, record the rejected Jira issue, PR, deployed SHA, previous deployed SHA, Salesforce deployment ID, rejection reason, affected metadata, and data-impact classification.
- Classify every original metadata change as modified, deleted, added, or manual-only. Restore previous versions for modified/deleted metadata and use an explicitly generated destructiveChanges.xml only to compensate for metadata added by the rejected issue.
- Destructive rollback requires reference analysis, impact assessment, check-only validation, and explicit DEV environment approval.
- Stop for manual resolution when a later deployed commit changed an affected component.
- Data mutations, irreversible org settings, and metadata transformations require a backup or compensating-operation runbook before merge.
- Rejection is complete only after rollback deployment and post-rollback validation succeed and the deployment evidence is recorded in Jira and GitHub.
```

### 4.2 Dedicated rollback workflow

**Artifact:** `.github/workflows/rollback-development.yml` (new)

Use `workflow_dispatch` with required inputs for Jira key, rejected deployed SHA, reviewed rollback SHA, and rejection reason. The job must use the protected `DEV` environment and the same `salesforce-development` concurrency group as the normal development deploy.

Required sequence:

1. Verify both SHAs belong to `develop` and the rollback commit reverses the rejected change.
2. Resolve the most recent successful `DEV` deployment from GitHub deployment history.
3. Detect later changes to affected components and stop on conflict.
4. Generate restoration and destructive manifests plus a machine-readable rollback plan.
5. Publish the plan before any persistent change.
6. Run a check-only validation.
7. Require explicit `DEV` approval for destructive, data-impacting, or irreversible operations.
8. Deploy the rollback.
9. Run declared post-rollback checks.
10. Publish the Salesforce deployment ID, SHAs, component list, and result.

The workflow must not create or merge the revert PR automatically.

### 4.3 Pull request evidence contract

**Artifacts:** `.github/pull_request_template.md` (new) and `.ai/GITHUB.md`

Every issue PR must include:

- Jira issue and Salesforce metadata scope;
- components added, modified, and removed;
- data-mutation and irreversible-configuration classification;
- expected sandbox and post-deploy validation;
- restoration, destructive rollback, backup, compensating-operation, and post-rollback steps;
- deployment and rollback evidence fields.

Non-applicable fields must be explicitly marked `N/A` with a reason. An agent must not declare an issue ready when a destructive, data-mutating, or irreversible operation lacks a recovery procedure. Creating a revert does not complete rejection handling; completion requires reconciliation of Git, `AXON_DEV`, and Jira.

### 4.4 Reverse-delta tooling

**Artifacts:**

- `scripts/ci/build-salesforce-rollback.sh`
- `scripts/ci/check-rollback-conflicts.sh`
- `scripts/ci/validate-salesforce-manifest.sh`

The builder receives the rejected base SHA, rejected deployed SHA, and rollback SHA. It emits `package.xml`, `destructiveChanges.xml`, `rollback-plan.json`, and `rollback-summary.md`.

For each component, the plan records metadata type, component name, original change classification, rollback action, conflict status, data impact, and approval requirement.

The tooling must:

- derive metadata types through supported project/Metadata API mappings rather than file extension alone;
- exclude unrelated deletions;
- stop for unsupported or ambiguous metadata;
- stop when later commits touch an affected component;
- keep destructive changes empty when no compensating removal is required;
- never persist credentials or sensitive payloads in artifacts.

The existing `list-salesforce-delta.sh` remains non-destructive and continues to serve ordinary deployments.

### 4.5 Rejection protocol

Use these operational states as structured evidence rather than adding global Jira workflow statuses:

```text
REJECTED_PENDING_REVERT
REVERT_READY
ROLLBACK_VALIDATING
ROLLBACK_APPROVAL_REQUIRED
ROLLBACK_RUNNING
ROLLBACK_FAILED
ROLLBACK_BLOCKED
ROLLED_BACK
```

When sandbox acceptance rejects an integrated issue:

1. Record the reason, evidence, owner, original PR, and deployed SHA in Jira.
2. Create a revert PR against `develop`.
3. Prevent overlapping changes to the affected components until the rollback is resolved.
4. Merge the reviewed revert.
5. Dispatch the rollback workflow.
6. Validate the restored sandbox behavior.
7. Record workflow URL, rollback SHA, deployment IDs, and result in Jira and GitHub.
8. Close the rejection activity only in `ROLLED_BACK` state.

## 5. Implementation Handoff

### Ownership

- **Product Owner / delivery owner:** create and prioritize the Jira Task; define how sandbox rejection is represented in current Jira fields.
- **Developer / DevOps agent:** implement scripts, workflow, templates, and repository rules in an issue-specific worktree.
- **Salesforce reviewer:** validate Metadata API mappings, destructive ordering, dependency/reference detection, and unsupported metadata behavior.
- **Repository reviewer:** validate protected-branch behavior, workflow permissions, concurrency, environment approval, and evidence retention.
- **Sandbox acceptance owner:** provide rejection evidence and validate post-rollback behavior.

### Implementation sequence

1. Create the Jira Task and issue worktree.
2. Add executable tests for reverse-delta classification and conflicts.
3. Implement manifest generation and validation.
4. Implement the rollback workflow with no persistent execution in initial test fixtures.
5. Add PR template and policy updates.
6. Exercise safe test cases against synthetic Git histories.
7. Validate a non-destructive rollback in `AXON_DEV` using explicitly authorized test metadata.
8. Validate a destructive rollback only with explicit authorization and disposable test metadata.
9. Record evidence and enable the workflow.

### Success criteria

- Modified metadata is restored to the prior version.
- Originally deleted metadata is restored.
- Originally added metadata is removed only through an approved destructive manifest.
- Later conflicting changes block rollback automatically.
- Data and irreversible changes cannot pass without a compensating runbook.
- Normal development deployment remains non-destructive.
- Deploy and rollback cannot run concurrently.
- GitHub and Jira contain real SHAs, workflow links, results, and Salesforce deployment IDs.
- An AI agent cannot close a rejected issue after creating only a Git revert.

## 6. Change Navigation Checklist

- [x] Trigger and evidence identified.
- [N/A] Triggering product story: this is a cross-cutting delivery-control gap.
- [x] Existing epics remain viable.
- [N/A] Epic scope, order, or priority change.
- [x] PRD reviewed; existing NFRs cover the requirement.
- [x] Architecture/recovery contracts reviewed for alignment.
- [N/A] UX impact.
- [x] CI/CD, scripts, documentation, testing, and evidence impacts identified.
- [x] Direct adjustment selected.
- [x] Older-branch sandbox overwrite rejected.
- [N/A] MVP scope reduction.
- [x] Incremental proposals reviewed and approved by the user.
- [x] Complete proposal approved by the user on 2026-08-26.
- [N/A] Sprint status update: no epic or story was added, removed, or renumbered by this proposal.

## 7. Approval and Handoff Record

- Approval: approved by the user on 2026-08-26.
- Change scope: Moderate.
- Routed to: Product Owner / delivery owner and Developer / DevOps agent, with Salesforce and repository review.
- Product Owner responsibility: create and prioritize the canonical Jira Task and define the Jira representation of sandbox rejection.
- Developer / DevOps responsibility: implement and test the approved repository policy, workflow, template, reverse-delta tooling, and evidence controls in an issue-specific worktree.
- Reviewer responsibility: verify Salesforce destructive safety, protected-branch behavior, concurrency, environment approvals, and evidence retention.
- Implementation authorization: not granted by this proposal approval; implementation begins through the canonical Jira Task and repository lifecycle.
