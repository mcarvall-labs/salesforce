---
title: 'AXF-17: Explicit manual confirmation tracking'
type: feature
created: '2026-09-07'
status: implemented-validated
contract_approval: approved
approved: '2026-09-08'
review_loop_iteration: 0
context: ['{project-root}/AGENTS.md']
---

<frozen-after-approval reason="human-owned intent — scope approved by Michel on 2026-09-08">

## Intent

**Problem:** Manual entries have no durable review queue integration. Jira AXF-17 comment 10330 releases manual pending confirmation/linkage and deterministic `PlanIdentityHash`/`FallbackKey` signals, but those keys identify unique effects: they are not advisory fingerprints of two legitimate similar transactions.

**Approved approach:** Materialize explicitly requested manual confirmation pendencies as ReviewItems, expose authorized administrative confirmation, and preserve replay/conflict protection at existing producers. All advisory duplicate suggestions and distinct-record overrides are deferred, not counted as fulfilled by replay protection. The active Jira description and approval comment 10356 are authoritative.

Authority: https://axon-personal-finances.atlassian.net/browse/AXF-17, comments 10135/10330; predecessors AXF-15/19 and ReviewItem foundation AXF-94; parent AXF-10. Source inspected at `23c8fff60827b4f90da2719ece016062973f8703`.

## Boundaries & Constraints

**Always:** Preserve financial values, existing ClientRequestId/SourceKey/PlanIdentityHash uniqueness and replay semantics. Read and resolve only with current CRUD/FLS, sharing, access to every referenced record and expected version. Use the common ReviewItem schema/resolver and a dedicated LWC controller. Show pending, conflict, failed and completed truthfully. Retain reason, actor, time and version; apply shared retention rules. Deliver a feature PR to develop without promotion to UAT/main.

**Approved scope:** The explicit wizard choice “Acompanhar confirmação” / “Track confirmation” creates the item only when selected. Absence of a bank/card never automatically creates a pending requirement. Resolution is administrative confirmation without financial settlement, reconciliation or linkage changes. These product decisions no longer require approval. Consume the focused shared resolver corrections from AXF-16 once integrated, and retention from AXF-101; absent/unapproved retention policy preserves evidence.

**Never:** Relax Unique fields, invent an advisory fingerprint, compare missing descriptions as empty strings, assign a PlanIdentityHash from financial similarity, change CSV identity, implement fuzzy matching, automatically merge/delete/block legitimate entries, or classify valid imported CSV/Pluggy facts as manual pendencies.

## I/O & Edge-Case Matrix

| Scenario | Input/state | Expected behavior | Failure handling |
|---|---|---|---|
| Manual follow-up | Authorized manual create explicitly requests confirmation | One financial entry and one OPEN item committed atomically | Roll back both on failure |
| Legitimate cash | Manual entry without bank/card, no follow-up selected | Create normally; no fabricated pending requirement | Existing validation |
| Replay | Same client operation and payload | Return existing entry/item, never reopen resolved item | Changed payload returns conflict |
| Identity collision | Existing producer receives its established key again | Existing replay/conflict response, no extra fact | Never reinterpret as similarity |
| Resolution | OPEN item, note and expected version, all references accessible | Resolve once with evidence; preserve financial entry | Stale/access loss leaves item pending |
| Imported fact | Normal CSV/Pluggy publication | No manual review item | Source problems retain their own types |

</frozen-after-approval>

## Code Map

- `force-app/main/default/classes/AXF_CLS_FinancialEntryService.cls:createEntry` creates manual FTX, with client replay and optional bank/card. Input has no description or plan identity. Its CONFIRMED status cannot be reused as review completion.
- `force-app/main/default/lwc/aXF_LWC_entryWizard/` provides four steps and final confirmation; integrate explicit follow-up intent without premature persistence.
- `force-app/main/default/classes/ALT_CLS_ReviewQueueService.cls` provides create/list/open/resolve. Shared security, locking and reference checks are owned by coordinated AXF-16 work; consume its reviewed contract, do not fork a second resolver.
- `force-app/main/default/objects/AXF_OBJ_FinancialTransaction__c/fields/AXF_FTX_EXI_PlanIdentityHash__c.field-meta.xml` is unique occurrence identity. `ALT_CLS_ContractAgendaService.cls` populates it; read-only for this story.
- `force-app/main/default/classes/AXF_CLS_PluggyFactIdentity.cls:fallback` is the approved normalized identity primitive, but no FallbackKey field exists in this baseline. Do not pretend this is available persisted data.
- `force-app/main/default/classes/AXF_CLS_CsvImportConfirmService.cls:rowSourceKey` uses a distinct established CSV SourceKey including running balance and parent. Preserve it.

## Tasks & Acceptance

**Execution under approved scope:**
- [x] `docs/implementation/spec-axf-17-manual-review-pendencies.md` — reconcile the decisions in Jira and freeze the approved intent.
- [x] `force-app/main/default/classes/ALT_CLS_ManualReviewService.cls` — add a typed manual producer using common queue creation and durable per-entry review identity; keep resolution in the shared resolver.
- [x] `force-app/main/default/classes/AXF_CLS_FinancialEntryService.cls` and `lwc/aXF_LWC_entryWizard/` — carry explicit pending intent, atomically create entry/item, preserve replay and legitimate distinct entries.
- [x] `force-app/main/default/classes/AXF_CLS_CTRL_ManualReview.cls` and `lwc/aXF_LWC_manualReview/` — add authorized list/detail/confirmation with reason, current state/version, loading/empty/error states and accessible focus behavior.
- [x] `force-app/main/default/permissionsets/AXF_PS_FinancialEntry.permissionset-meta.xml`, relevant Custom Labels/translations and component exposure metadata — grant minimal access and translated labels, never Delete/ViewAll.
- [x] Focused Apex/Jest tests adjacent to changed services/components — cover the matrix, denied records/fields, concurrent resolution, replay after resolution and atomic failure.

**Acceptance Criteria:**
- Given a permitted manual follow-up request, when the user confirms the wizard, then its durable pending item is available without Home being implemented.
- Given an authorized pending item, when explicitly confirmed with a reason, then it closes once without changing financial amount, identity or linkage.
- Given distinct legitimate manual operations, when both are confirmed, then both remain distinct; no similarity policy is implied.

## Spec Change Log

- 2026-09-08: Michel approved the scoped architecture recommendation. Jira active criteria updated; comment 10356 preserves previous requirements. Scope approved; source implementation and validation remain outstanding.

## Design Notes

The original AC1 candidate evidence and AC2 override after a duplicate suggestion are explicitly deferred by the approved scope, not fulfilled. Comment 10356 and the active Jira description supersede the conflicting interpretation of comment 10330. AXF-13 identity rules remain intact. Record the administrative producer's typed references and handler mapping before integration; never route it into a financial matching handler. Refresh the baseline before consuming AXF-16 changes.

## Verification

Run targeted Jest, ESLint and formatting checks; inspect the final diff and XML dependencies. Coordinate check-only Salesforce validation and targeted Apex tests with the root agent; never run concurrent shared-org mutation/test jobs. Record actual results, commit and PR only after required checks. Check-only validation and focused test evidence are recorded below.


### Implementation and verification — 2026-09-09

- Based on develop 596e1f3, including the AXF-94 queue and AXF-16 resolver corrections.
- Explicit tracking intent is part of creation replay identity. Entry and MANUAL_CONFIRMATION item persist atomically. Cash without opt-in remains valid.
- The dedicated queue tab filters by type before the row limit, validates reference access through the shared service, and records a note/version without financial mutation.
- New permissions grant controller/tab access and tracking field access without Delete or broad sharing. Labels support PT-BR and EN.
- AXON_DEV check-only validation `0Afaj00000jeTasCAE`: Succeeded; 25 Apex tests passed, zero component/test errors, no coverage warnings. Includes denial of review permission with rollback of the financial entry.
- Jest: 10/10 tests passed, including opt-in payload, pending/empty/error states and conflict retention. ESLint passed. Code Analyzer: 0 severity 1/2 findings; 13 moderate and 13 low findings.
- Concurrency evidence is the common resolver locking/version implementation and stale-version tests; no live two-session load test or deployment was performed.
- Advisory similarity detection remains explicitly deferred under the approved Jira scope.
