---
title: 'AXF-83 Company responsible access'
type: 'feature'
created: '2026-09-01'
status: 'done'
review_loop_iteration: 0
baseline_commit: '96bb36f0b67defa42349ae42db5d77cfd80fbac2'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** AXF-83 must persist a person-to-business responsibility and grant an eligible linked user limited financial access without confusing the business role with Salesforce administration. The interrupted implementation already deploys but can overwrite or revoke independent Account Team and AccountContactRelation records, can grant without the required team role, and does not fully protect operational state from direct mutation.

**Approach:** Harden the existing AccountContactRelation + Account Team design around explicit Axon provenance, idempotent state, fail-closed role validation, atomic optimistic concurrency, and preservation of independent grants. Deliver Business Account access now; add child-object sharing reasons only when those child objects are introduced.

## Boundaries & Constraints

**Always:** Use acronyms `CRA` for CompanyResponsibleAccess and `ACR` for AccountContactRelation; use current field type prefixes `DT` and `BOL`. Require `AXF_CanConfigure`, Business/Person record types, the exact Account Team role `Responsável Financeiro`, and an AXF-82 eligible user before granting access. Preserve business relationships for people without users. Treat Account Team, AccountContactRelation, CRUD/FLS, PSG, ownership, and other grants as cumulative independent causes. Keep operational grant state service-controlled and fail closed.

**Ask First:** Any new financial child object, child-object sharing reason, destructive migration of already-deployed field API names, production operation, or change to the approved Team Role.

**Never:** Create future financial objects for this story; remove or repurpose manual/package Account Team members; deactivate a pre-existing non-Axon AccountContactRelation; grant Delete, View All, Modify All, System Administrator, or Gestor role; create users implicitly; commit `d83.json`; deploy to AXON_PROD.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| New responsibility | Business, person, role; eligible user | Managed relation, durable CRA state, Axon-owned Account Team Edit grant | Return verified `GRANTED` only after all effects exist |
| Person without user | Valid business/person/role | Persist managed business relation and `RELATIONSHIP_ONLY`; no User or Account Team member | Safe pending outcome |
| Existing independent records | Manual Account Team member or non-Axon ACR exists | Preserve it unchanged; create or track only Axon-owned effects | Refuse ambiguous takeover rather than mutate independent state |
| Missing Team Role | `Responsável Financeiro` absent | No Account Team grant and no optimistic success | Persist/report controlled failure suitable for retry |
| Replay or stale update | Same request or outdated version | No duplicates; exact replay is stable; stale request conflicts | `CONFLICT` without overwrite |
| Revoke/reactivate | Axon-owned grant plus other access causes | Remove only AXF-83 effects; preserve other grants; reactivation clears stale revocation state | Report effective verified state |

</frozen-after-approval>

## Code Map

- `C:/Projects/Axon Finance/.worktrees/salesforce/claude-axf-83/force-app/main/default/classes/ALT_CLS_AxonCompanyResponsible.cls` -- domain service; grant/revoke provenance, concurrency, role validation, and state transitions.
- `C:/Projects/Axon Finance/.worktrees/salesforce/claude-axf-83/force-app/main/default/classes/AXF_CLS_CTRL_CompanyResponsible.cls` -- dedicated thin LWC entry point and user-mode account search.
- `C:/Projects/Axon Finance/.worktrees/salesforce/claude-axf-83/force-app/main/default/classes/ALT_CLS_AxonCompanyResponsibleTest.cls` -- functional, idempotency, independent-rights, and failure-path coverage.
- `C:/Projects/Axon Finance/.worktrees/salesforce/claude-axf-83/force-app/main/default/classes/AXF_CLS_CTRL_CompanyResponsibleTest.cls` -- controller authority and delegation coverage.
- `C:/Projects/Axon Finance/.worktrees/salesforce/claude-axf-83/force-app/main/default/objects/AXF_OBJ_CompanyResponsibleAccess__c` -- durable per-pair operational state; rename field prefixes and track necessary transitions.
- `C:/Projects/Axon Finance/.worktrees/salesforce/claude-axf-83/force-app/main/default/objects/AccountContactRelation` -- managed marker and business-role fields using approved naming.
- `C:/Projects/Axon Finance/.worktrees/salesforce/claude-axf-83/force-app/main/default/permissionsets/AXF_PS_GestorFinanceiro.permissionset-meta.xml` -- least-privilege access; operational fields must not permit state fabrication.
- `C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/ARCHITECTURE-SPINE.md` -- read-only G2/G3 authority.
- `C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/SHARING-MATRIX.md` -- read-only independent-rights and surface fixtures.

## Tasks & Acceptance

**Execution:**
- [x] `ALT_CLS_AxonCompanyResponsible.cls` -- make grant/revoke provenance-safe, lock durable state, fail closed on missing role, and keep transitions internally consistent.
- [x] `AXF_CLS_CTRL_CompanyResponsible.cls` -- retain a thin authorized boundary and safe errors without reusable business logic.
- [x] `ALT_CLS_AxonCompanyResponsibleTest.cls` and `AXF_CLS_CTRL_CompanyResponsibleTest.cls` -- cover the entire edge-case matrix, including pre-existing independent records and reactivation.
- [x] `AXF_OBJ_CompanyResponsibleAccess__c` and `AccountContactRelation` metadata -- apply approved `CRA`/`ACR` and `DT`/`BOL` conventions, preserve deployability, and record meaningful state history.
- [x] `AXF_PS_GestorFinanceiro.permissionset-meta.xml` -- expose only the least privilege needed by the UI/service and prevent direct operational-state tampering.
- [x] AXON_DEV -- retrieve targeted dependencies, deploy only the delta, run targeted tests, and verify actual Account Team/relationship effects with sanitized fixtures.

**Acceptance Criteria:**
- Given a valid responsible person, when confirmation completes, then the relationship and only the AXF-83 Account Team access are persisted and verified without administrative escalation.
- Given no eligible User, when responsibility is confirmed, then the business relation remains pending without implicit user or record-access creation.
- Given independent access or relationship records, when AXF-83 grants, retries, revokes, or reactivates, then those independent records remain unchanged.
- Given a missing role, stale version, duplicate request, or partial failure, when processing occurs, then no unverified success or duplicate effect is reported.
- Given no financial child objects in this branch, when AXF-83 is delivered, then no speculative child metadata is created and the limitation is documented for later object-specific sharing.

## Spec Change Log

## Design Notes

The CRA record is the provenance anchor for AXF-83 effects, not a replacement for Salesforce record access. The implementation must distinguish an Axon-created/owned Account Team effect from an unrelated member for the same account/user. If Salesforce cannot encode that distinction on AccountTeamMember, store the precise managed effect identity in durable state or fail safely rather than adopting an existing record.

## Verification

**Commands:**
- `npx prettier --check "force-app/main/default/classes/*CompanyResponsible*.cls" "force-app/main/default/objects/AXF_OBJ_CompanyResponsibleAccess__c/**/*.xml" "force-app/main/default/objects/AccountContactRelation/**/*.xml"` -- expected: no formatting drift.
- `sf code-analyzer run --workspace force-app/main/default/classes/ALT_CLS_AxonCompanyResponsible.cls --workspace force-app/main/default/classes/AXF_CLS_CTRL_CompanyResponsible.cls` -- expected: no unresolved high-severity findings.
- `sf project deploy start --source-dir <AXF-83-delta> --target-org AXON_DEV` -- expected: successful targeted deployment only.
- `sf apex run test --tests ALT_CLS_AxonCompanyResponsibleTest --tests AXF_CLS_CTRL_CompanyResponsibleTest --target-org AXON_DEV --wait 30 --code-coverage --result-format human` -- expected: all targeted tests pass with coverage evidence.

**Manual checks (if no CLI):**
- Verify the exact Team Role and both org toggles remain enabled; confirm grants and revocations with two responsible users, one unrelated user, a manual team member, and a pre-existing non-Axon relationship.

**Execution evidence:**
- Targeted deployment `0Afaj00000iq0YsCAI` succeeded in `AXON_DEV` after audit fixes.
- Apex run `707aj00001CJ8B5` passed 23/23 tests; service coverage 92%, controller coverage 97%.
- Prettier and `git diff --check` passed. Critical/high PMD findings: none.
- Project owner confirmed both org toggles and the exact Team Role `Responsável Financeiro`; a later local CLI describe attempt was inconclusive because Node failed with `ENOMEM` before connecting.
- Final targeted deployment `0Afaj00000iqVeHCAU` succeeded in `AXON_DEV`.
- Final Apex run `707aj00001CHGAa` passed 34/34 tests; service coverage 88%, controller coverage 97%.
- Three independent post-patch reviews found no remaining security, edge-case, or verification gaps.

## Suggested Review Order

**Access lifecycle and provenance**

- Start with the responsibility state machine, optimistic concurrency, and fail-safe outcomes.
  [`ALT_CLS_AxonCompanyResponsible.cls:151`](../../../.worktrees/salesforce/claude-axf-83/force-app/main/default/classes/ALT_CLS_AxonCompanyResponsible.cls#L151)

- Review access-first revocation and preservation of unrelated grants.
  [`ALT_CLS_AxonCompanyResponsible.cls:406`](../../../.worktrees/salesforce/claude-axf-83/force-app/main/default/classes/ALT_CLS_AxonCompanyResponsible.cls#L406)

- Inspect managed relationship ownership, repair, and sanitized failure handling.
  [`ALT_CLS_AxonCompanyResponsible.cls:473`](../../../.worktrees/salesforce/claude-axf-83/force-app/main/default/classes/ALT_CLS_AxonCompanyResponsible.cls#L473)

- Inspect exact Account Team ownership, minimum access, and drift repair.
  [`ALT_CLS_AxonCompanyResponsible.cls:547`](../../../.worktrees/salesforce/claude-axf-83/force-app/main/default/classes/ALT_CLS_AxonCompanyResponsible.cls#L547)

**Authorized presentation boundary**

- Verify user-mode search validation and wildcard enumeration protection.
  [`AXF_CLS_CTRL_CompanyResponsible.cls:31`](../../../.worktrees/salesforce/claude-axf-83/force-app/main/default/classes/AXF_CLS_CTRL_CompanyResponsible.cls#L31)

- Verify list redaction for inaccessible Person and User identifiers.
  [`ALT_CLS_AxonCompanyResponsible.cls:348`](../../../.worktrees/salesforce/claude-axf-83/force-app/main/default/classes/ALT_CLS_AxonCompanyResponsible.cls#L348)

**Schema and permissions**

- Review durable provenance, versioning, status, and audit fields.
  [`AXF_OBJ_CompanyResponsibleAccess__c.object-meta.xml:1`](../../../.worktrees/salesforce/claude-axf-83/force-app/main/default/objects/AXF_OBJ_CompanyResponsibleAccess__c/AXF_OBJ_CompanyResponsibleAccess__c.object-meta.xml#L1)

- Review the ACR managed marker and business-role vocabulary.
  [`AXF_ACR_BOL_AxonManaged__c.field-meta.xml:1`](../../../.worktrees/salesforce/claude-axf-83/force-app/main/default/objects/AccountContactRelation/fields/AXF_ACR_BOL_AxonManaged__c.field-meta.xml#L1)

- Confirm least-privilege read-only relationship metadata access.
  [`AXF_PS_GestorFinanceiro.permissionset-meta.xml:168`](../../../.worktrees/salesforce/claude-axf-83/force-app/main/default/permissionsets/AXF_PS_GestorFinanceiro.permissionset-meta.xml#L168)

**Verification**

- Review functional, concurrency, independence, reactivation, and failure-path coverage.
  [`ALT_CLS_AxonCompanyResponsibleTest.cls:1`](../../../.worktrees/salesforce/claude-axf-83/force-app/main/default/classes/ALT_CLS_AxonCompanyResponsibleTest.cls#L1)

- Review controller authorization, input validation, and delegation coverage.
  [`AXF_CLS_CTRL_CompanyResponsibleTest.cls:1`](../../../.worktrees/salesforce/claude-axf-83/force-app/main/default/classes/AXF_CLS_CTRL_CompanyResponsibleTest.cls#L1)
