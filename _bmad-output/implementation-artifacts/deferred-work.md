- source_spec: `C:\Projects\Axon Finance\Salesforce\_bmad-output\implementation-artifacts\spec-allow-portuguese-technical-documentation.md`
  summary: Make the canonical `.ai/PROJECT_RULES.md` policy reproducible and reviewable through version control.
  evidence: `.ai/` is excluded by `.git/info/exclude` and `.ai/PROJECT_RULES.md` does not exist in HEAD, so the applied local policy cannot be inspected with a normal Git diff or distributed to collaborators; changing the exclusion or tracking mechanism was outside the approved scope.

## AXF-126 — Economic allocation (code review 2026-09-15, PR #109)

- **Set ownership drift** — `AXF_OBJ_EconomicAllocationSet__c.OwnerId` is set from the holder's owner at propose time; a later Account owner change does not re-home existing sets. Needs an Account owner-change handler (shared with AXF-119 orchestrator runs).
- **Guard write window is public** — `ALT_CLS_EconomicAllocationGuard.beginWrite()/endWrite()` are public because the service and the guard test both need them; consider a `@TestVisible` seam plus a service-only entry.
- **Participante read path** — `OWN_SHARE_ONLY` visibility for participants is described but has no consumer; the LWC only renders for record access + `AXF_CanAllocate`.
- **Fact edits after confirmation** — `ALT_CLS_RealizationGuard.originals` only freezes facts referenced by realization allocations; a confirmed economic allocation does not freeze the fact, so drift is only detected on the next confirm (`FACT_CHANGED`).
- **Attributed account is in use, but never backfilled** — AXF-127 now writes `AXF_EAS_LKP_AttributedAccount__c` on the `DRAFT → CONFIRMED` transition and clears it when the set is discarded, so "remove" is off the table; the remaining gap is history: sets confirmed under AXF-126 keep a permanently null projection, because the guard freezes the field after confirmation and no service path can repair it (backfill script vs. accepted hole — needs a decision).
- **Non-owner proposer cannot persist its access** — `ALT_CLS_EconomicAllocationService.grantProposerAccess()` writes the Manual share with `allOrNone=false`, so its rejection is silent; a user who does not own the holder account (and therefore not the set) cannot read the set it just created nor write its own access share (`INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY`), and `propose()` then fails inserting the parcel. Measured while looking for a non-owner fixture for AXF-127/G3.

## AXF-122 — Consolidated totals (code review 2026-09-15, PR #111)

- **Joint holders** — `ALT_CLS_ConsolidationService` attributes each source to `AXF_BA/CC_LKP_Account__c` only; `AXF_OBJ_AccountHolder__c` (AXF-85 PRIMARY/SECOND/THIRD) is ignored. Needs a domain decision (split rule vs. allocation-only) before the sum can claim joint accounts.
- **Unverified holder facts** — facts of `UNKNOWN` holders are never loaded, so confirmed shares attributed _into_ the authorized scope from those facts are lost without a reason. Would require loading facts by allocation set rather than by source.
- **Private confirmed sets** — an EAS the caller cannot see (OWD Private) yields holder attribution silently; only object/field access degrades. Consider `ALT_CLS_EconomicAllocationIntegrity` (without sharing, ids only) to detect "set exists but unreadable".
- **Capability packaging** — `AXF_CanConsolidate` lives in the Gestor PS instead of a per-capability PS like `AXF_PS_Realization`.
- **Effective window echo** — `Result.fromDate/toDate` echo the input; the effective bounds (platform Date range when null) are not returned.
- **CI test level** — PRs to `develop` deploy with `NoTestRun`; Apex evidence comes from the manual AXON_DEV deploy recorded in the PR.

## AXF-109 — Observation adapter (code review 2026-09-15, PR #110)

- **Enrichment never reaches existing facts** — `ALT_CLS_SourceChangeReview.reconcile` inserts new identities only; `MATERIAL` does not include `RawSourceStatus/OperationType/ProviderCategory/MerchantName/Installment*`, and a `PKL_Status` change opens a `SOURCE_CHANGE` review that `ALT_CLS_ReviewQueueService.resolve` reports as `SOURCE_RESOLUTION_UNAVAILABLE`. Facts imported before AXF-109 stay `STATUS_MISSING`; a PENDING fact never becomes ELIGIBLE. Requires the source-change resolution design (pre-existing) plus a backfill.
- **Re-classification** — the fingerprint is content-only; bumping `CLASSIFICATION_VERSION` does not re-observe existing rows. Add an explicit `reclassify` entry point when S2 needs it.
- **Inactive owner** — `OwnerId = holder.OwnerId` fails with `INACTIVE_OWNER_OR_USER` instead of a typed code.
- **Admin surface** — no layout/list view for `AXF_OBJ_TransactionObservation__c`.
- **Joint holders** — observation context is the source's primary holder (same limitation as AXF-122).

## AXF-143 — Confidence panel (code review 2026-09-15, PR #112)

- **Holder selector truncation** — `listHolders()` is `LIMIT 200` with no truncation flag or search; reuse `ALT_CLS_AxonHolder.listHolders(search)` and surface "more than 200".
- **Per-source freshness limit UX** — `AXF_BA/CC_NUM_FreshnessLimitHours__c` are editable only via API; no layout/flexipage field, no validation rule for ≤ 0 (falls back to the policy default silently).
- **Allowed actions** — `OPEN_SOURCE` / `REVIEW_SOURCE_HEALTH` are rendered as text; wire `REVIEW_SOURCE_HEALTH` to the `AXF_SourceHealth` tab.
- **Gestor-only evidence** — tests assign `AXF_PS_PluggyIntegration` to Gestor users; confirm a production Gestor alone can read `AXF_OBJ_PluggyConnection__c` fields or grant them in the Gestor PS.
- **Account OWD assumption** — `NOT_AUTHORIZED` tests rely on Account OWD Private, which is org configuration, not source.

## AXF-95 — Transaction archive (code review 2026-09-15, PR #114)

- **Archiver permission set** — `AXF_PS_GestorFinanceiro` grants read/create + FLS on `AXF_OBJ_TransactionArchive__b` because the batch writer runs as the Gestor and big-object fields are invisible without FLS; via API a Gestor can query the whole archive (big objects have no sharing). Move the grants to a dedicated archiver PS or run the batch under an integration user.
- **Hot totals at scale** — `ALT_CLS_ArchiveRunService.hotTotals` is one aggregate over the holder's whole pre-window scope; >50k hot rows would exceed the query-row limit in `finish()`. Accumulate per chunk in the Stateful batch instead.
- **Optimistic version** — `AXF_ARR_NUM_Version__c` is incremented on every checkpoint but never compared; concurrent writers are prevented only by the job/in-progress guard.
- **UI** — confirmation dialog is hand-rolled (focus/Escape handled) — `lightning-modal` would be the platform answer; no scheduled runs; the AXON_DEV quirk (system mode does not bypass sharing under `runAs`) makes `RUN_OWNED_BY_OTHER` untestable there (test accepts `RUN_IN_PROGRESS` as the unique-key answer).

## AXF-137 — Forecast horizons and scenarios (code review 2026-09-15, PR #116)

- **Holder picker** — the LWC wires `getContext(search: "")`; `listAuthorizedContexts`/`listHolders` cap at 200 with no truncation flag. Add a search input and a "more than 200" indicator.
- **Non-ACTIVE schedules with open occurrences** — DRAFT/ENDED schedules carrying persisted OPEN occurrences are excluded by both paths (schedule and standalone plan); decide whether they are commitments and add a `SCHEDULE_NOT_ACTIVE` reason.
- **Beyond-horizon text** — `beyondRows` interpolates raw decimals and ISO dates; use `lightning-formatted-*` like the tables.
- **`masterLabel` language** — bundle master labels are EN while tabs/permissions are PT-BR (unaccented); align once a project-wide convention is written down.
- **Apex tests are not a develop CI gate** — `salesforce-delivery.mjs` deploys with `NoTestRun` on DEV; Apex evidence stays a manual AXON_DEV run until UAT/PROD (pre-existing).

## AXF-134 — Bank/card source link (code review 2026-09-15, PR #117)

- **Holder picker** — same as AXF-137: no search, `listAuthorizedContexts` LIMIT 200 treated as denial beyond the cap.
- **`getContext` cacheable** — `canLink` is cached client-side until a hard refresh after an admin grants the capability.
- **Review opened between eligibility check and AXF-25 lock** — a review created after `evaluate()` and before `apply` locks the fact is not seen; the single-command lock belongs to AXF-136.
- **`finish()` after commit** — if the freshly inserted allocation is not readable by the user, `confirm` answers `UNAVAILABLE` although the link persisted; return the known values instead of re-reading.
- **`MAX_SCHEDULES` = 12** — schedules ordered by Id for virtual context; order by next due date and consider raising the limit (SOQL budget: ~7 queries per projection).

## AXF-139 — Candidate evidence (code review 2026-09-15, PR #118)

- **Virtual lines** — funding and category always `UNKNOWN`; read them from the schedule's active definition so a schedule funded by the same account can be evidenced.
- **Server-side sort mode** — the due-date re-sort is page-local; add `sortMode` to `CandidateQuery` applied before pagination if users need "earliest due first" across pages.
- **Explanation labels per feature** — only DATE_AFTER/BEFORE and the containment directions have dedicated texts; the other explanation codes fall back to the relation label.
- **`REDACTED`** — reserved; a cross-holder evaluation that must withhold values would need SYSTEM_MODE reads plus explicit redaction (USER_MODE fails closed today).

## AXF-141 — Reconciliation reversal (code review 2026-09-15, PR #119)

- **Concurrent second reversal** — the wrapper's `ALREADY_REVERSED` pre-check runs before the AXF-25 lock; the loser of a race answers `CONFLICT` (documented). A post-lock re-check needs a hook inside AXF-25.
- **ACTUAL_ONLY after reversal** — the born FTX keeps magnitude/role with no derived marker; consumers must use AXF-25 `read` (documented). A derived "reversed" indicator on the plan would help list views/dashboards.
- **`getContext`** — cacheable with an unused `search` argument (same as the other capability tabs).
- **AXF-104 boundary** — obligation adjustment / recurring-reference recomputation after reversing a schedule occurrence is flagged (`AXF104_OBLIGATION_ADJUSTMENT_PENDING`), not performed; AXF-104/AXF-142.

## AXF-78 — DEV cleanup execution (2026-09-15, validation `0Afaj00000kQtWDCA0`)

- **`AXF_CLS_AccessConfigEffectiveTest.systemAdministratorIsNotAConfiguradorByDefault`** fails on AXON_DEV: the admin user that runs `RunLocalTests` holds `AXF_CanConfigure` through the `AXF_PSG_GestorFinanceiro` assignment made so the Axon apps are visible (AXF-77 step 4). The assertion assumes a bare System Administrator; either run the check under `System.runAs` of a freshly built admin or drop the org-state assumption.
- **`AXF_CLS_HolderAccessTest.gestorCanRegisterAndEditButNotDelete`** fails on AXON_DEV (`saveHolder` → `FAILED` for the built Gestor). Reproduces standalone before and after the cleanup; root cause not investigated here (org data/config drift suspected — the same test was green when AXF-85 merged).
- **Sites infrastructure left org-only** — 7 error/template pages, 3 components and the `SiteSamples` static resource remain in AXON_DEV and in no branch because the `Pluggy_Webhook` CustomSite (manual install step, AXF-11 §10) references them. Bringing the site + minimal AXF-owned pages into Git would close that drift; needs a decision on org-specific values (`siteAdmin`, guest owner).
