---
title: 'AXF-86 Manual financial sources'
type: 'feature'
created: '2026-09-02'
status: 'in-review'
review_loop_iteration: 0
baseline_commit: '600f523c6091a9c9dd9a84c58daf2f82d31df08b'
context:
  - '{project-root}/project-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Authorized users cannot create bank accounts or credit cards that are not covered by Pluggy. A manual source must have explicit ownership and currency without fabricating integration identity or bypassing the private access model.

**Approach:** Add a reusable manual-source form backed by a dedicated controller and domain service. Create the source and one confirmed `PRIMARY` AccountHolder atomically, persist a UUID-based manual identity, synchronize the denormalized primary-holder lookup and owner, and keep Pluggy discovery behavior isolated.

## Boundaries & Constraints

**Always:** Validate `AXF_CanConfigure`, CRUD/FLS, record access, `AXF_Person|AXF_Business`, active currency, institution, UUID idempotency key, expected version, and all client IDs server-side. Keep BankAccount/CreditCard private; set owner from the authorized holder Account owner; grant no Delete. Treat AccountHolder as ownership authority and the BA/CC Account lookup as a projection. Store only masked account/card values. Manual identity and Pluggy identity are mutually exclusive. Return typed, sanitized outcomes including `CREATED|ALREADY|UPDATED|CONFLICT|FORBIDDEN|INVALID|FAILED`.

**Ask First:** Any need to change the approved holder roles/states, create a bank-account relationship for cards, introduce a new source object, change Pluggy identity, or broaden participant access.

**Never:** Create fake Pluggy IDs, connections, holders, bank accounts, transactions, CSV imports, balances from inference, or automatic manual↔Pluggy merges. Do not implement multiple holders, holder correction/revocation, AXF-85/AXF-8 flows, Household, CommandExecution, or AuditEvent. Do not change holder/currency on a used source or store full account/card numbers.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Create bank/card | Accessible holder, active ISO currency, institution, new UUID | Source + confirmed PRIMARY ACH committed; projection/owner synchronized; AVAILABLE | Atomic rollback on any failure |
| Safe replay | Same kind and UUID, same payload | Existing result returned without duplicate effects | `ALREADY` |
| Conflicting replay | Same UUID with different payload/kind | No overwrite | `CONFLICT` |
| Unauthorized/invisible | Missing permission or inaccessible holder/source | No existence disclosure or DML | Stable `FORBIDDEN` |
| Invalid source | Inactive currency, invalid RT, blank institution, unmasked sensitive value | No records | Field-safe `INVALID` |
| Edit | Expected version matches; descriptive fields only; holder/currency unchanged | Allowed fields updated once | Stale=`CONFLICT`; protected mutation rejected |
| Skip onboarding step | User skips `MANUAL_SOURCES` | Zero BA/CC/ACH records; onboarding continues | Existing skip result retained |

</frozen-after-approval>

## Code Map

- `force-app/main/default/classes/ALT_CLS_AxonHolder.cls:122` -- reuse configure authority, USER_MODE queries, typed DTOs, and safe outcomes.
- `force-app/main/default/classes/AXF_CLS_CTRL_Holder.cls:9` -- controller-per-LWC delegation pattern; keep reusable logic in the service.
- `force-app/main/default/classes/AXF_CLS_PluggyDiscoveryService.cls:380` -- read-only integration path to preserve; Pluggy uses provider ID, Connection, and CUSTODY.
- `force-app/main/default/classes/AXF_CLS_PluggyDiscoveryServiceTest.cls:16` -- regression anchor proving discovery/replay remains isolated.
- `force-app/main/default/classes/ALT_CLS_AxonOnboardingProgress.cls:47` -- existing optional `MANUAL_SOURCES` step; skip must create nothing.
- `force-app/main/default/objects/AXF_OBJ_BankAccount__c/fields/AXF_BA_LKP_Account__c.field-meta.xml:3` -- current optional projection; manual service must synchronize it.
- `force-app/main/default/objects/AXF_OBJ_CreditCard__c/fields/AXF_CC_LKP_Account__c.field-meta.xml:3` -- current optional projection; no invented bank-account link.
- `force-app/main/default/permissionsets/AXF_PS_GestorFinanceiro.permissionset-meta.xml:157` -- preserve existing BA/CC least privilege and add only required ACH/manual FLS.
- `C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/ARCHITECTURE-SPINE.md:307` -- read-only G1/G2/G6 authority for ACH, ownership, access, and idempotency.

## Tasks & Acceptance

**Execution:**
- [x] `force-app/main/default/objects/AXF_OBJ_AccountHolder__c/**` -- create the private ACH root, holder/target XOR, PRIMARY confirmation, validity, version, and unique framed key metadata.
- [x] `force-app/main/default/objects/AXF_OBJ_BankAccount__c/**` and `AXF_OBJ_CreditCard__c/**` -- add separate unique ManualKey identity and metadata validation without weakening AXF-84 Pluggy fields.
- [x] `force-app/main/default/classes/ALT_CLS_ManualFinancialSource.cls` -- implement authorized atomic create/replay/edit with locking, projection/owner sync, currency validation, and safe results.
- [x] `force-app/main/default/classes/AXF_CLS_CTRL_ManualFinancialSource.cls` -- expose only the dedicated thin LWC boundary.
- [x] `force-app/main/default/lwc/aXF_LWC_manualFinancialSource/**` -- deliver accessible PT-BR/EN create/edit/skip states reusable by onboarding and Configuration.
- [x] `force-app/main/default/permissionsets/AXF_PS_GestorFinanceiro.permissionset-meta.xml` and translations -- grant least privilege and localized labels; no participant/Delete escalation.
- [x] Apex/Jest tests -- cover the full matrix, real permission behavior, atomic rollback, owner/projection consistency, and Pluggy regression.

**Acceptance Criteria:**
- Given an authorized user and accessible person or business holder, when a valid manual source is saved, then one usable source and one confirmed PRIMARY ACH exist with no Pluggy identity or connection.
- Given a replay, stale edit, denied holder, invalid currency, or partial failure, when processed, then no duplicate, unauthorized disclosure, fabricated identity, or partial ownership effect remains.
- Given an existing Pluggy-discovered source, when AXF-86 runs or discovery replays, then its provider identity, connection, CUSTODY state, and unrelated rights remain unchanged.
- Given the optional onboarding step is skipped, when progress resumes, then no empty source exists and later Configuration use remains available.

## Spec Change Log

## Design Notes

The UUID ManualKey identifies the create operation, not business similarity. The service derives the ACH key with length-prefixed framing of holder, target type, target ID, and role. BA/CC holder lookups remain optional in schema while AXF-84 custody records may legitimately lack a confirmed holder; AXF-86 enforces holder and AVAILABLE atomically for manual records. This is an expand-compatible bridge until AXF-85 completes broader holder lifecycle and backfill.

## Verification

**Commands:**
- `npx prettier --check "force-app/main/default/classes/*ManualFinancialSource*.cls" "force-app/main/default/lwc/aXF_LWC_manualFinancialSource/**/*" "force-app/main/default/objects/AXF_OBJ_AccountHolder__c/**/*.xml"` -- expected: no formatting drift.
- `sf code-analyzer run --workspace force-app/main/default/classes/ALT_CLS_ManualFinancialSource.cls --workspace force-app/main/default/classes/AXF_CLS_CTRL_ManualFinancialSource.cls` -- expected: no unresolved high-severity findings.
- `sf project deploy start --source-dir <AXF-86-delta> --target-org AXON_DEV` -- expected: targeted deployment succeeds without broad retrieval/deploy.
- `sf apex run test --tests ALT_CLS_ManualFinancialSourceTest --tests AXF_CLS_CTRL_ManualFinancialSourceTest --target-org AXON_DEV --wait 30 --code-coverage --result-format human` -- expected: all targeted tests pass.
- `npm test -- --runInBand aXF_LWC_manualFinancialSource` -- expected: component states and accessibility tests pass.

**Manual checks (if no CLI):**
- Verify account/card create, safe replay, skip, forbidden holder, inactive currency, and keyboard/screen-reader error focus without exposing full numbers.

**Execution evidence (2026-09-02):**
- Salesforce validation job `0Afaj00000iv59hCAA`: succeeded; 52 components, 0 component errors, 10/10 tests passed in 5,052 ms.
- Apex coverage: `ALT_CLS_ManualFinancialSource` 80.89%; `AXF_CLS_CTRL_ManualFinancialSource` 100%.
- Matrix audit: create bank/card, replay, conflicting/cross-kind replay, forbidden access, inactive currency, invalid Account record type, blank institution, masked-value validation, versioned edit, protected holder/currency mutation with invariant ACH/projection, onboarding skip, and Pluggy identity/connection/CUSTODY preservation all ran and passed.
- Jest: 1 suite and 2/2 tests passed, covering bilingual rendering and skip without save.
- Code Analyzer: 0 High findings; the single Critical was an environment-only Flow-engine prerequisite (Python >=3.10 unavailable), not a finding in the changed Apex.
- Prettier, XML parsing, and `git diff --check`: passed.
