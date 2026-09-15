# AXF-106 — Documentation and backlog reconciliation

Date: 2026-09-12. Authorized by Michel. Jira remains requirement/status authority: https://axon-personal-finances.atlassian.net/browse/AXF-106

## Current decision

Decision approved by Michel on 2026-09-12; authoritative scope: AXF-106. This active supplement supersedes conflicting bank-reference and onboarding-order assumptions in this document only. It is a requirement change, not evidence of implementation, migration or deployment.

Reuse the Financial Institution object reported in production as the canonical bank directory. Its exact API name/schema and availability in DEV/UAT still require read-only verification. Do not create a duplicate object or infer schema from a label.

Connections select Bank through a Lookup to that directory and a suggested Holder through a Lookup to Account (AXF_Person / AXF_Business). Register/reuse holders before connections; provide inline New holder without losing Item ID or bank selection. Holder registration creates no User and grants no access.

Bank accounts, credit cards, manual-source forms and relevant selectors, filters, reports and integrations consume canonical institution references. Preserve provider connector/institution text and IDs separately. MeuPluggy, name similarity or bank equality never proves bank mapping, source identity or ownership.

Connection holder remains a suggestion. Confirm the holder per account/card through AXF-85 before financial use. Editing connection references must not rewrite confirmed holders, grants, financial facts, allocations or immutable document/archive snapshots.

Display bank and holder names plus masked Item ID; support multiple connections sharing bank/holder, explicit edits, idempotent registration and rediscovery. Existing missing references remain visible pending decisions. An alias-only solution does not satisfy this decision.

Inventory consumers before migration; map only unambiguous associations, report unresolved/conflicting mappings, preserve original values and require repeatable backfill and rollback. Do not delete legacy fields until consumers and parity checks pass. Production mutation and destructive cutover require separate authorization.

Open implementation decisions: verified institution identifiers; mandatory fields/progression gates; inactive/deleted-reference policy; and connections with sources from different banks. Do not impose a blanket required-field retrofit or invent a new automatic mapping rule.

Preserve Dev Done and later work-item history. AXF-106 owns the evolution of delivered AXF-80/84/85/86/88/89/90/91/98. Related open work receives only its applicable compatibility obligations; unrelated reviewed contracts/readiness are not reopened.

## Updated Jira items and scoped impact

| Item | Status at inspection | Impact |
| --- | --- | --- |
| [AXF-1](https://axon-personal-finances.atlassian.net/browse/AXF-1) | Tarefas pendentes | Holder registration precedes connection selection and grants no User or access. Account remains the holder root; confirmed source ownership remains distinct from the suggested connection holder. |
| [AXF-4](https://axon-personal-finances.atlassian.net/browse/AXF-4) | Tarefas pendentes | When consolidation displays or filters a source bank, resolve the canonical institution relationship. Authorization and economic totals continue to use confirmed source holders; never the connection suggestion. |
| [AXF-5](https://axon-personal-finances.atlassian.net/browse/AXF-5) | Tarefas pendentes | Account ownership and economic allocation must continue using confirmed source holders. The connection holder is only a suggestion and cannot create allocations, debt, or shares. |
| [AXF-9](https://axon-personal-finances.atlassian.net/browse/AXF-9) | Backlog | Include institution/holder references in the export and lifecycle inventory where present. Preserve referential integrity and the bank directory when still referenced; no cascade deletion or new retention policy follows from AXF-106. |
| [AXF-10](https://axon-personal-finances.atlassian.net/browse/AXF-10) | Tarefas pendentes | Include AXF-106 in this epic's active scope: reuse the existing production institution directory, bank/source Lookups and holder selection before connection discovery. |
| [AXF-26](https://axon-personal-finances.atlassian.net/browse/AXF-26) | Tarefas pendentes | Financial-source selectors and labels consume canonical bank references; bank equality and connection holder suggestions never establish reconciliation eligibility or ownership. |
| [AXF-28](https://axon-personal-finances.atlassian.net/browse/AXF-28) | Tarefas pendentes | Show source bank through its canonical institution relationship and use the confirmed account/card holder for eligibility. Preserve typed source IDs and immutable original facts; missing bank mapping is a visible administrative pending state, not grounds to fabricate facts or ownership. |
| [AXF-29](https://axon-personal-finances.atlassian.net/browse/AXF-29) | Tarefas pendentes | Bank names/relationships may explain candidates but never prove identity or ownership. Use confirmed source holders, canonical institution labels and existing matching rules without changing scores or tolerances. |
| [AXF-30](https://axon-personal-finances.atlassian.net/browse/AXF-30) | Tarefas pendentes | Use canonical bank labels in the N:N source selector; preserve typed source identity, confirmed-holder authorization and conservation. A shared bank or suggested holder cannot authorize a match. |
| [AXF-31](https://axon-personal-finances.atlassian.net/browse/AXF-31) | Tarefas pendentes | Connection bank/holder edits must not rewrite confirmed allocations or their reversal evidence. Resolve current bank labels by relationship while preserving historical evidence. |
| [AXF-32](https://axon-personal-finances.atlassian.net/browse/AXF-32) | Tarefas pendentes | Identify origin/destination accounts using canonical institutions and confirmed source holders. Bank equality or connection holder selection alone does not establish an internal transfer. |
| [AXF-34](https://axon-personal-finances.atlassian.net/browse/AXF-34) | Tarefas pendentes | Card/bill consumers use the card's canonical institution reference. Preserve provider connector/bill identity and confirmed card ownership; same bank does not imply the same card. |
| [AXF-37](https://axon-personal-finances.atlassian.net/browse/AXF-37) | Tarefas pendentes | Resolve bank labels/filters from the card institution relationship. Preserve the five independent dimensions, original monetary evidence and confirmed-holder authorization. |
| [AXF-38](https://axon-personal-finances.atlassian.net/browse/AXF-38) | Tarefas pendentes | Display bank payment sources and cards with canonical institution labels; verify confirmed ownership and existing payment rules. Shared institution or connection suggestion does not create a card/account association. |
| [AXF-47](https://axon-personal-finances.atlassian.net/browse/AXF-47) | Tarefas pendentes | Bank filters, source labels and drill-downs use canonical institution relationships. Onboarding links support holder registration before connection selection; financial totals use confirmed source holders only. |
| [AXF-48](https://axon-personal-finances.atlassian.net/browse/AXF-48) | Tarefas pendentes | Distinguish bank-mapping pending, suggested connection holder, confirmed source ownership and provider freshness. A renamed/missing directory label is not proof of synchronization failure or altered monetary values. |
| [AXF-58](https://axon-personal-finances.atlassian.net/browse/AXF-58) | Tarefas pendentes | Bank movement selectors in FX flows consume canonical bank references while retaining original FX evidence and confirmed source ownership. |
| [AXF-60](https://axon-personal-finances.atlassian.net/browse/AXF-60) | Tarefas pendentes | Display linked movement banks through canonical institution references. Preserve actual source IDs, confirmed-holder access and original currency; bank equality is not a matching or conservation rule. |
| [AXF-65](https://axon-personal-finances.atlassian.net/browse/AXF-65) | Tarefas pendentes | Where bank/account information is selected for a billing draft, resolve the canonical institution relationship and authorized source. Never use a connection-holder suggestion as the creditor/contractual counterparty. |
| [AXF-66](https://axon-personal-finances.atlassian.net/browse/AXF-66) | Tarefas pendentes | Capture any required bank name in the immutable issued-document snapshot from the validated source/reference at issuance. Subsequent directory renaming must not rewrite an issued document. |
| [AXF-70](https://axon-personal-finances.atlassian.net/browse/AXF-70) | Tarefas pendentes | Use canonical bank labels for receipt-source selection and confirmed source holders for authorization; preserve original source identity, contractual party and single revenue recognition. |
| [AXF-72](https://axon-personal-finances.atlassian.net/browse/AXF-72) | Tarefas pendentes | New CSV formats map bank identity to the shared institution directory through a verified unambiguous rule, preserving raw provider text and source IDs. Do not create an independent bank-name authority or infer holder from the bank. |
| [AXF-77](https://axon-personal-finances.atlassian.net/browse/AXF-77) | Em andamento | Impact on in-progress installation scope: include the existing institution object's verified metadata/dependencies and authorized reference-data provisioning in the distribution plan. Update both READMEs and test holder registration before connections, inline New holder, bank/holder Lookups, multiple Item IDs and confirmation per source. Do not clone production customer data. AXF-106 integration is required for acceptance of this changed onboarding slice, not for unrelated installation investigation. |
| [AXF-78](https://axon-personal-finances.atlassian.net/browse/AXF-78) | Tarefas pendentes | Retain/reuse the existing Financial Institution object. Add legacy bank text fields to the consumer/migration inventory, but remove none until AXF-106 replacements, mappings, tests, backup and explicit destructive authorization are verified. Preserve provider raw evidence. |
| [AXF-79](https://axon-personal-finances.atlassian.net/browse/AXF-79) | Tarefas pendentes | Include AXF-106 institution reuse and source-bank/holder references in DEV/UAT/PROD delta, dependency and migration plans. Require unambiguous mapping, unresolved/conflict reporting, repeatable backfill, rollback and preserved production identities/history. No blanket required-field retrofit or production mutation is authorized by this update. |
| [AXF-81](https://axon-personal-finances.atlassian.net/browse/AXF-81) | Tarefas pendentes | Add AXF-106 as the evolution of delivered onboarding stories. Register/reuse person/company holders before connection registration; allow inline New holder with form preservation; select bank and suggested holder on each connection; discover; then confirm per account/card. Preserve optional access provisioning/manual sources/currency/review and resumable progress. |
| [AXF-95](https://axon-personal-finances.atlassian.net/browse/AXF-95) | Backlog | If archive records/readers include institution identity, define the canonical ID and any necessary historical label snapshot explicitly. Directory edits cannot mutate immutable archive evidence, resurrect data or substitute a connection suggestion for confirmed-holder authorization. |
| [AXF-100](https://axon-personal-finances.atlassian.net/browse/AXF-100) | Tarefas pendentes | Resolve card bank through the canonical institution relationship while preserving Pluggy connector, card and bill IDs. Never match bills by bank name or assign ownership from the suggested connection holder. |
| [AXF-102](https://axon-personal-finances.atlassian.net/browse/AXF-102) | Tarefas pendentes | Include institution-reference and historical-label behavior in the source-to-archive mapping if bank data is archived. Verify supported field/index/read behavior rather than assuming relational joins; do not reopen unrelated feasibility gates. |
| [AXF-103](https://axon-personal-finances.atlassian.net/browse/AXF-103) | Tarefas pendentes | Where schedules select/display a bank source, reuse the canonical institution relationship and confirmed source-holder authorization. Connection suggestion and directory-name changes do not change holder locks, schedule amounts, frozen bases or historical source identity. |
| [AXF-104](https://axon-personal-finances.atlassian.net/browse/AXF-104) | Tarefas pendentes | Use confirmed source ownership for settlement and holder-first locking. Connection-holder edits and directory renames do not rewrite settlement evidence, adjustments, recurring references or monetary allocations. |
| [AXF-106](https://axon-personal-finances.atlassian.net/browse/AXF-106) | Backlog | Project-wide reconciliation requested on 2026-09-12: current canonical documents and related pre-Dev-Done work items adopt this decision. Preserve delivered US acceptance criteria/status; AXF-106 owns their implementation evolution. Integrate the revised onboarding with installation AXF-77, cleanup AXF-78 and production migration AXF-79; downstream consumers inherit only applicable bank-reference and confirmed-ownership constraints, not a blanket new build gate. |

## Canonical pages

- [PRD — Axon Finance](https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=2490369)
- [Adendo do PRD — Axon Finance](https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=2523137)
- [SPEC Canônica — Axon Finance](https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=3670017)
- [Especificação de UX — Axon Finance](https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=2686977)
- [Arquitetura Salesforce — Axon Finance](https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=3604482)
- [Dicionário de Schema — Axon Finance](https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=3735553)
- [Contratos de Implementação — Axon Finance](https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=3801089)
- [Matriz de Sharing — Axon Finance](https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=5210113)
- [Guia do Desenvolvedor — Axon Finance](https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=3866625)
- [Rastreabilidade da SPEC — Axon Finance](https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=3702785)
- [Prontidão da definição — gates do modelo nativo e onboarding](https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=7569409)
- [Correção de curso — modelo nativo e onboarding completo — 2026-08-27](https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=7536641)
- [Disposição arquitetural — modelo nativo e onboarding — 2026-08-27](https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=7733249)
- [UX — Modelo de Experiência](https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=4063233)
- [UX — Design e Componentes](https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=4096001)
- [Documentação do Produto — Axon Finance](https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=2457601)
- [Registro de Operações — Axon Finance](https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=5177345)
- [Contrato Operacional — Axon Finance](https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=5636097)

## Local synchronization

- C:/Projects/Axon Finance/_bmad-output/planning-artifacts/prds/prd-Axon-Finance-2026-08-20/prd.md
- C:/Projects/Axon Finance/_bmad-output/planning-artifacts/prds/prd-Axon-Finance-2026-08-20/addendum.md
- C:/Projects/Axon Finance/_bmad-output/specs/spec-axon-finance/SPEC.md
- C:/Projects/Axon Finance/_bmad-output/specs/spec-axon-finance/traceability.md
- C:/Projects/Axon Finance/_bmad-output/specs/spec-axon-finance/readiness.md
- C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/ARCHITECTURE-SPINE.md
- C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/SCHEMA-DICTIONARY.md
- C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/IMPLEMENTATION-CONTRACTS.md
- C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/SHARING-MATRIX.md
- C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/DEVELOPER-GUIDE.md
- C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/RECONCILIATION-CONTRACT.md
- C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/OPERATION-REGISTRY.md
- C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/OPERATIONS-CONTRACT.md
- C:/Projects/Axon Finance/_bmad-output/planning-artifacts/ux-designs/ux-Axon-Finance-2026-08-21/EXPERIENCE.md
- C:/Projects/Axon Finance/_bmad-output/planning-artifacts/ux-designs/ux-Axon-Finance-2026-08-21/DESIGN.md
- C:/Projects/Axon Finance/_bmad-output/planning-artifacts/sprint-change-proposal-native-onboarding-2026-08-27.md
- C:/Projects/Axon Finance/_bmad-output/planning-artifacts/epics.md
- C:/Projects/Axon Finance/Salesforce/_bmad-output/planning-artifacts/epics.md
- C:/Projects/Axon Finance/Salesforce/docs/PROJECT_WIKI.md
- C:/Projects/Axon Finance/Salesforce/docs/SALESFORCE_DELIVERY.md
- C:/Projects/Axon Finance/Salesforce/_bmad-output/implementation-artifacts/epic-1-context.md
- C:/Projects/Axon Finance/Salesforce/_bmad-output/planning-artifacts/AXF-106-developer-handoff.md

## Preserved history and limits

All 106 Jira items and the 63-page AXF Confluence index were inventoried. Dev Done and later items, canceled/superseded work, unrelated scopes and historical review/backup artifacts are preserved. Delivered holder/discovery/wizard changes belong to AXF-106, not retrospective acceptance-criteria edits. Domain epic supplements cover subordinate bank consumers; stories without bank selection, ownership or migration changes retain their original scope. No new blanket dependency is imposed on unrelated financial implementation.

Production object identity/schema and actual runtime compatibility remain unverified; no Salesforce metadata/data operations, source changes, deploy, commit, push or merge are included. Documentation updates do not imply tests passed or gates closed. Verify live Jira and current Confluence before implementation.

## Final verification

- 32 Jira items verified after update: full ADF description matches the expected scoped supplement plus original content; status, assignee and parent preserved.
- 21 Confluence pages verified: 18 core pages plus AXF-28/103/104 implementation contracts. Prior content preserved; page 7536641 only gained a converter-generated task-list local ID, with identical prior text.
- 25 existing local documents updated, plus this reconciliation record (26 local documents total). Existing front matter and historical content preserved. Marker/encoding checks and git diff --check passed for the checked local set.
- Additional canonical/local contracts: https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=15171596 (AXF-28), https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=15138817 (AXF-103), https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=15138849 (AXF-104). Local counterparts are in _bmad-output/planning-artifacts/architecture/architecture-AXF-28-2026-09-10/.
- AXF-77 comment records impact on already-started installation work. AXF-106 comment records project-wide traceability.

