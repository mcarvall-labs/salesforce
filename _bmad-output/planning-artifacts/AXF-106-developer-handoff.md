<!-- AXF-106-DECISION-20260912 -->
## AXF-106 — current bank and holder decision (2026-09-12)

Acceptance integration: AXF-106 AC1–AC10 govern institution reuse, onboarding, mapping, migration and consumer compatibility. Test existing wizard resume, ambiguous banks, inaccessible lookups and unchanged confirmed source holders.

Decision approved by Michel on 2026-09-12; authoritative scope: AXF-106. This active supplement supersedes conflicting bank-reference and onboarding-order assumptions in this document only. It is a requirement change, not evidence of implementation, migration or deployment.

Reuse the Financial Institution object reported in production as the canonical bank directory. Its exact API name/schema and availability in DEV/UAT still require read-only verification. Do not create a duplicate object or infer schema from a label.

Connections select Bank through a Lookup to that directory and a suggested Holder through a Lookup to Account (AXF_Person / AXF_Business). Register/reuse holders before connections; provide inline New holder without losing Item ID or bank selection. Holder registration creates no User and grants no access.

Bank accounts, credit cards, manual-source forms and relevant selectors, filters, reports and integrations consume canonical institution references. Preserve provider connector/institution text and IDs separately. MeuPluggy, name similarity or bank equality never proves bank mapping, source identity or ownership.

Connection holder remains a suggestion. Confirm the holder per account/card through AXF-85 before financial use. Editing connection references must not rewrite confirmed holders, grants, financial facts, allocations or immutable document/archive snapshots.

Display bank and holder names plus masked Item ID; support multiple connections sharing bank/holder, explicit edits, idempotent registration and rediscovery. Existing missing references remain visible pending decisions. An alias-only solution does not satisfy this decision.

Inventory consumers before migration; map only unambiguous associations, report unresolved/conflicting mappings, preserve original values and require repeatable backfill and rollback. Do not delete legacy fields until consumers and parity checks pass. Production mutation and destructive cutover require separate authorization.

Open implementation decisions: verified institution identifiers; mandatory fields/progression gates; inactive/deleted-reference policy; and connections with sources from different banks. Do not impose a blanket required-field retrofit or invent a new automatic mapping rule.

Preserve Dev Done and later work-item history. AXF-106 owns the evolution of delivered AXF-80/84/85/86/88/89/90/91/98. Related open work receives only its applicable compatibility obligations; unrelated reviewed contracts/readiness are not reopened.

Canonical page: https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=3670017

Requirements: https://axon-personal-finances.atlassian.net/browse/AXF-106

<!-- /AXF-106-DECISION-20260912 -->

# AXF-106 — Developer handoff

Authoritative requirements: https://axon-personal-finances.atlassian.net/browse/AXF-106

Created 2026-09-12 at the user's request. This is a handoff snapshot, not an independent specification. Read the live Jira issue before implementation. No source, org configuration or deployment was changed.

## Context and decisions
The administrator currently sees connections with generic connector names such as MeuPluggy. The user confirmed that production contains an existing Financial Institution object. Its API name, schema, data and availability in DEV/UAT have NOT been verified. Do not create a duplicate institution object or invent its API name.

This improvement supersedes the earlier alias-only proposal: bank and holder must be selected from existing records, not inferred from free text. No separate alias field is required by this story.

## User Story
As an authorized administrator, I want to register holders before connections and select the financial institution and holder for each Pluggy connection, so that I can identify connections clearly and confirm ownership of discovered accounts and cards safely.

## Functional scope
- Reuse the production Financial Institution object as the canonical bank directory.
- Add institution and holder Lookups to AXF_OBJ_PluggyConnection__c; holder references Account (AXF_Person / AXF_Business).
- Use institution relationships wherever the application represents a bank: connections, bank accounts, credit cards, manual sources, relevant screens, queries, filters and reports.
- Preserve original provider institution/connector names and identifiers as integration evidence. Connector identity is not bank identity.
- Reuse holder registration from AXF-80. Holder registration is separate from user creation and access provisioning.
- Connection holder is a suggested holder only. Confirm financial ownership per account/card through AXF-85.

## Acceptance Criteria
### AC1 — Existing institution directory
Given the production object reported by the user, when technical discovery starts, document its exact API name, identifiers, relationships, permissions and availability in DEV/UAT using read-only inspection. Reuse it; provide a targeted environment-alignment plan before implementation. Do not copy production customer or credential data.

### AC2 — Holder registration before connections
Given a new onboarding session, when preparing connections, offer a holder registration step before connection registration, allowing selection/reuse or creation of person/company Accounts through AXF-80. Preserve the remaining credential, discovery, confirmation, access, manual-source, currency and review capabilities. Adapt progress and persisted step state so existing sessions can resume without restarting or duplicating completed work.

### AC3 — Create a holder inline
Given an unfinished connection form, when the administrator chooses New holder from the holder selection, allow authorized person/company creation and return with that holder selected without losing Item ID or bank selection. Cancellation preserves the form. Do not create a User or grant access.

### AC4 — Connection selection and display
Given an authorized administrator and available reference records, allow selecting bank and holder through searchable Lookups during connection registration and editing them later. Display bank and holder names plus masked Item ID, consent, discovery status and counts. Save references, not duplicated display-name text. Missing references on existing connections remain visibly pending and editable; do not fabricate records or invalidate existing connections silently.

### AC5 — Multiple connections and idempotency
Given different Item IDs, preserve separate connections, including multiple connections at the same bank or for the same holder. Re-entering an existing Item ID does not duplicate it or silently overwrite bank/holder selections; changes require explicit editing. Reload and rediscovery preserve saved selections.

### AC6 — Explicit source ownership
Given a connection with a selected holder, discovery presents that holder as a suggestion for its accounts/cards. Explicit confirmation through AXF-85 is still required per source, with overrides allowed for valid persons/companies. Unconfirmed sources remain protected. Editing the connection holder does not rewrite confirmed source holders, historical transactions, access grants or economic attribution.

### AC7 — Canonical bank references
Given a verified inventory of current bank usages, replace bank-name text as the application reference with the canonical institution relationship in applicable connections, accounts, cards, manual-source forms, selectors, filters and reports. Display the current directory name via the relationship. Preserve original external names/IDs and historically meaningful snapshots; do not perform an indiscriminate text replacement.

### AC8 — Provider mapping and conflicts
Given provider connector/institution data, map it to canonical institutions only through a verified, unambiguous rule. Generic MeuPluggy or matching names alone must not assign a bank. Preserve unknown/conflicting mappings as explicit pending decisions; never overwrite a manual bank selection silently. Validate source-level bank assignments instead of assuming a connector always represents one institution.

### AC9 — Migration and compatibility
Given existing records, provide a dry-run mapping report with mapped, unresolved and conflicting counts and no sensitive data. Backfill only unambiguous associations; require explicit resolution for the rest. Make migration repeatable and document rollback. Do not remove legacy fields until consumers, integrations, reports and reconciliation checks pass. Production execution requires separate authorization.

### AC10 — Security and usability
Enforce sharing, CRUD/FLS and administrator authority on selection, creation and updates. Reject unauthorized/stale record references without data leakage. Deliver accessible PT-BR/EN labels, empty/loading/error states, save/cancel behavior and clear distinction between bank, provider connector, suggested connection holder and confirmed source holder.

## Technical reconnaissance and decisions to close
- Exact Financial Institution API name and authoritative business identifiers.
- Existing bank references, legacy consumers and migration volume across environments.
- Whether bank/holder are mandatory on new connections and which wizard transition is gated; the user authorized selection, not a blanket required-field retrofit.
- Policy for deactivated/deleted institutions and Accounts; avoid cascading source deletion.
- Handling of connections whose discovered sources belong to different institutions.
Record these findings in this issue before dependent implementation. Do not invent business rules.

## Dependencies and traceability
Parent: AXF-10, Financial sources.
Related: AXF-80 (holder registration), AXF-84 (discovery), AXF-85 (source holder confirmation), AXF-86 (manual sources), AXF-90 (wizard), AXF-98 (multiple Item IDs and connection registration). Preserve their historical acceptance criteria.

## Validation
Test person/company selection and inline creation/cancel; multiple connections sharing bank/holder; duplicate Item ID; edits and reload; unchanged confirmed holders after connection edit; generic connector and conflicting mapping; legacy records with missing references; migration replay and rollback; report/filter consistency; denied permissions; PT-BR/EN and wizard resume. Use targeted Apex/Jest tests and authorized integrated validation; mocks alone do not prove environment alignment.

## Out of scope and delivery
No automatic financial ownership/access from connection selection, User creation, authentication rewrite, global text replacement, destructive field deletion or production data migration in this definition task. This issue defines scope; it does not authorize deploy, commit, push or merge. Definition of Done: accepted scope implemented, dependencies resolved, relevant tests passed, migration and rollback evidence documented, and delivery status advanced only through verified project gates.
