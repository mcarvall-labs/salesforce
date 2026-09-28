# Destructive backlog

Tracking-only. Nothing here executes anything — it is not read by the pipeline.
It exists so the legacy-cleanup candidates found while building the destructive-changes
feature (#145/#148, see PR #148's review comment for the full method) aren't only
remembered as a GitHub comment. To actually apply an entry, copy its class name into
`manifest/destructiveChangesPost.xml` (see `manifest/README.md`) in a reviewed PR —
re-verify against the live target org first, since this list can go stale.

Jira: [AXF-161](https://axon-personal-finances.atlassian.net/browse/AXF-161) tracks
this end to end. Update this file and that ticket together — never record a
destructive-cleanup candidate only in chat history or a PR comment.

## Status: applied to DEV — rebaseline on AXON_PROD + AXON - Configuration (26/09/2026)

Owner decision (26/09/2026): the project baseline is the AXON_PROD content plus only the
AXON - Configuration app and onboarding wizard. The previous rebuild is archived as git tag
`archive/greenfield-2026-09` (branch `rebaseline/prod-plus-config`). **This supersedes the
"AXON_PROD legacy Apex classes" section below: those classes are now the baseline and must
NOT be deleted** (see the list kept below only for the audit trail).

Applied to AXON_DEV on 26/09/2026 (explicitly approved by the owner, each phase dry-run first):

| Phase | Deploy id                   | What                                                                                                                                                                                         |
| ----- | --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0     | data                        | Rebuild permission set / group assignments removed; rebuild bank accounts, cards, Pluggy connections, account holders and integration runs deleted                                           |
| 1a    | `0Afaj00000lsOThCAM`        | Account, BankInstitution, BankAccount, CreditCard record pages deactivated (View override -> Default)                                                                                        |
| 1b    | `0Afaj00000lsOgbCAE`        | 460 code components: all rebuild Apex classes/triggers, LWCs, custom tabs, FlexiPages, both rebuild apps, AXF_PSG__, 10 AXF_PS__, candidate named/external credential, notification types    |
| 2     | `0Afaj00000lsPZRCA2`        | 1,559 data-model components: 48 rebuild objects (incl. CMDTs, platform event, big object), 83 rebuild fields on kept objects, 1,410 labels, 16 custom permissions, validation rules, layouts |
| 3     | `0Afaj00000lsU2rCAE`        | Baseline deployed (664 components, RunLocalTests 332/332)                                                                                                                                    |
| 4     | data + `0Afaj00000lsVF3CAM` | Groups re-assigned; holders moved to PersonAccount; `PersonAccount.AXF_Person` deactivated (record types cannot be deleted through the API — delete it in Setup)                             |

Kept on purpose in AXON_DEV: list view `AXF_OBJ_BankAccountTransaction__c.All` (last filter of the object).

### Candidates still open (not applied)

- `ZZZ_TestNameField` (AXON_PROD only): obsolete debug class, removed from the repository.
- Production home components replaced by the `AXF_Home` dashboard — **applied to AXON_DEV on
  28/09/2026** (`0Afaj00000m1JwDCAU`, RunLocalTests 321/321): `AXF_HPL_HomePage`,
  `aXF_LWC_monthlyBalanceKpi`, `aXF_LWC_overdueExpensesAlert`, `aXF_LWC_overdueRevenuesAlert`,
  `aXF_LWC_expenseHomeTable`, `aXF_LWC_revenueHomeTable`, `aXF_LWC_investmentCapacityKpi`,
  their controllers, `ALT_CLS_CashFlowAlerts`, `ALT_CLS_InvestmentCapacity`,
  `AXF_CLS_CashFlowHomeController`, `AXF_CLS_SVC_CashFlowBalance`,
  `AXF_CLS_SVC_CashFlowSettlement` and 20 labels. Pending for UAT/PROD with the promotion.
- AXON_PROD will need, at promotion time: Account settings (account teams, contacts to
  multiple accounts, versioned in `settings/Account.settings-meta.xml`) and the
  `SalesTeamRole` value `Responsável Financeiro`.

## Status: pending decision — AXON_PROD legacy Apex classes

Found via `sf org list metadata --metadata-type ApexClass --target-org AXON_PROD`
compared against `main`'s git history (2026-09-17): 62 classes live in AXON_PROD with
no git history in any branch (pre-greenfield legacy, never tracked).

### 52 candidates — no live reference found (safe to re-verify and apply)

Cross-checked against every live `ApexClass`/`ApexTrigger` body in AXON_PROD via
Tooling API SOQL; none of these are referenced by anything outside this set.
Re-run that check before applying — this is a snapshot, not a guarantee it still holds.

```
ALT_CLS_AccountLookup, ALT_CLS_BankAccountBalance, ALT_CLS_BankAccountStatement,
ALT_CLS_CashFlowAlerts, ALT_CLS_CashFlowHome, ALT_CLS_CashFlowSettlement,
ALT_CLS_CategoryLookup, ALT_CLS_Consortium, ALT_CLS_CreditCardStatement,
ALT_CLS_FinancialAccountLookup, ALT_CLS_InvestmentCapacity, ALT_CLS_ManualSync,
ALT_CLS_PriceFinancing, AXF_CLS_BankAccountBalanceController,
AXF_CLS_BankAccountStatementController, AXF_CLS_CTRL_AccountLookup,
AXF_CLS_CTRL_BankAccountLookup, AXF_CLS_CTRL_BankAccountStatement,
AXF_CLS_CTRL_Category, AXF_CLS_CTRL_CategoryLookup, AXF_CLS_CTRL_CategoryTest,
AXF_CLS_CTRL_CreditCardLookup, AXF_CLS_CTRL_CreditCardStatement,
AXF_CLS_CTRL_ExpenseHomeTable, AXF_CLS_CTRL_InvestmentCapacityKPI,
AXF_CLS_CTRL_MonthlyBalanceKPI, AXF_CLS_CTRL_OverdueExpensesAlert,
AXF_CLS_CTRL_OverdueRevenuesAlert, AXF_CLS_CTRL_PluggyManualSync,
AXF_CLS_CTRL_QuickFlowActions, AXF_CLS_CTRL_QuickFlowActions_Test,
AXF_CLS_CTRL_RealTimeBalance, AXF_CLS_CTRL_RevenueHomeTable,
AXF_CLS_CTRL_SyncAllAccounts, AXF_CLS_CashFlowHomeController,
AXF_CLS_CreditCardStatementController, AXF_CLS_ManualSyncController,
AXF_CLS_PluggyAccountSync_Service, AXF_CLS_PluggyBalanceSync_Service,
AXF_CLS_PluggyBankAccountSyncQueueable, AXF_CLS_PluggyBillSync_Service,
AXF_CLS_PluggyCategorySync_Service, AXF_CLS_PluggyCreditCardSyncQueueable,
AXF_CLS_PluggyInvSync_Service, AXF_CLS_PluggyItemSyncQueueable,
AXF_CLS_PluggyLoanSync_Service, AXF_CLS_PluggyRetryScheduler,
AXF_CLS_PluggyTxSync_Service, AXF_CLS_SVC_CashFlowBalance,
AXF_CLS_SVC_CashFlowSettlement, AXF_TH_CreditCardInvoice, ZZZ_TestNameField
```

(51 listed here — `ALT_CLS_SacFinancing` was in the original 52 but moved to the
excluded table below; count kept for audit trail, see git history of this file.)

### Excluded — confirmed still in live use as of 2026-09-17, do NOT delete without re-checking

| Class                             | Reason                                                                                                            |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `ALT_CLS_SacFinancing`            | Referenced by live trigger `AXF_TRG_InstallmentGroup`                                                             |
| `AXF_CLS_TH_AccountCardNaming`    | Referenced by live triggers `AXF_TRG_BankAccount`, `AXF_TRG_CreditCard`                                           |
| `AXF_CLS_TH_BankInstitution`      | Referenced by live trigger `AXF_TRG_BankInstitution`                                                              |
| `AXF_CLS_TH_CashFlow`             | Referenced by live trigger `AXF_TRG_CashFlow`                                                                     |
| `AXF_CLS_TH_Reconciliation`       | Referenced by live triggers `AXF_TRG_CashFlow`, `AXF_TRG_BankAccountTransaction`, `AXF_TRG_CreditCardTransaction` |
| `AXF_CLS_PluggyItemSyncScheduler` | Matches active `CronTrigger` "AXF Pluggy Item Sync - Daily"                                                       |

### Never applicable — managed package, Salesforce rejects deletion

`devedapp__DeveloperEditionUtils`, `devedapp__DeveloperEditionUtilsTest`,
`devedapp__PostInstallScript`, `devedapp__PostInstallScriptTest` — auto-installed
Developer Edition package components, not deletable via destructiveChanges.

### Scope note

Only `ApexClass` was checked. Other metadata types (`CustomObject`, `CustomField`,
`PermissionSet`, `LWC`, etc.) were **not** compared against AXON_PROD — this list is
known to be incomplete beyond Apex classes.

### AXON_UAT status (checked 2026-09-17, ApexClass only)

No drift: every class in `uat` branch is deployed, and the only untracked classes in
the org are `AXF_CLS_ScratchDebugTest` (likely a manual scratch artifact, low risk)
and the same 4 `devedapp__` managed-package classes above. No destructive action
needed for UAT **on ApexClass**. See the LWC/CustomObject finding below — this
ApexClass-only check does not mean UAT is clean overall.

### AXON_DEV status

Checked 2026-09-28 for LWC/CustomObject (see below). Clean. Other metadata types
(CustomField, PermissionSet, Flow, etc.) still not checked — pending in AXF-161.

## Status: pending decision — greenfield LWC/CustomObject leftovers on AXON_UAT (2026-09-28)

Found while triaging the 208 "could not be mapped automatically" deletions PR #185's CI
evidence (`aXF_LWC_*` bundles and `objectTranslations/*` for greenfield-only objects,
removed from `force-app` by the rebaseline). LightningComponentBundle and CustomObject
deletions are deliberately never auto-resolved by `scripts/ci/salesforce-delivery.mjs`
(see its `TOP_LEVEL_DESTRUCTIVE_TYPES` comment) — each needed live-org re-verification
instead of trusting the evidence file, per this doc's own instructions above.

Cross-checked via `sf org list metadata --metadata-type LightningComponentBundle` and
`--metadata-type CustomObject` against AXON_DEV, AXON_UAT and AXON_PROD:

- **AXON_DEV — clean.** None of the 30 `aXF_LWC_*` bundles or 10 greenfield-only objects
  (`AXF_CMT_RetentionPolicy__mdt`, `AXF_OBJ_FinancialSchedule__c`,
  `AXF_OBJ_FinancialTransaction__c`, `AXF_OBJ_FxApplicationSnapshot__c`,
  `AXF_OBJ_IntegrationRun__c`, `AXF_OBJ_ReconciliationAllocation__c`,
  `AXF_OBJ_ReviewItem__c`, `AXF_OBJ_ScheduleChange__c`, `AXF_OBJ_ScheduleDefinition__c`,
  `AXF_OBJ_ScheduleReference__c`) still exist — already removed by this file's 26/09
  phased rebaseline (phases 1b/2). **No manifest entry needed for DEV.**
- **AXON_PROD — clean.** Never had the greenfield rebuild. **No manifest entry needed.**
- **AXON_UAT — still fully live.** All 10 objects and 24 of the 30 LWC bundles are still
  deployed; UAT was never put through the 26/09 rebaseline DEV got. The 6 bundles NOT
  found on UAT (`aXF_LWC_bankStatement`, `aXF_LWC_cardStatement`, `aXF_LWC_financings`,
  `aXF_LWC_manualEntries`, `aXF_LWC_reconciliationQueue`, `aXF_LWC_recurrences`) are later
  sprint deliverables that never reached the `uat` branch before the owner's pivot.

**Not a simple destructive-changes PR.** UAT is still running the greenfield app, not the
AXON_PROD-legacy baseline — deleting these 40 components via
`manifest/destructiveChangesPost.xml` (which applies through the normal
`develop → uat → main` promotion, with no per-environment phasing) would break UAT's
current app without the equivalent of DEV's phased, dry-run-first rebaseline. Treat as its
own owner-approved rebaseline pass on UAT, same method as `docs/destructive-backlog.md`'s
26/09 DEV entry above, not a manifest entry copied in as-is.

## Status: applied to DEV/UAT, pending PROD — AXF-159 Console app migration

`manifest/destructiveChangesPre.xml` carried this destructive delete-and-recreate
(same API name, `navType: Standard -> Console`) through `develop` and `uat` on
23-24/09/2026 — see AXF-159. Emptied back out on 24/09/2026 once both confirmed
working, per this file's own process (copy into a reviewed PR when actually
applying, don't leave it live in between).

```
CustomApplication: AXF_CA_AxonFinance
CustomApplication: AXF_CA_AxonConfiguration
```

| Environment | Status      | Verified                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ----------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AXON_DEV    | Applied     | Visual validation in browser 24/09/2026 — Console nav, correct tabs both apps                                                                                                                                                                                                                                                                                                                                             |
| AXON_UAT    | Applied     | Visual validation in browser 24/09/2026 — Console nav, correct tabs both apps                                                                                                                                                                                                                                                                                                                                             |
| AXON_PROD   | **Pending** | Not yet promoted. When promoting this branch to `main`: re-populate `manifest/destructiveChangesPre.xml` with these two `CustomApplication` members, redeploy `AXF_PS_GestorFinanceiro`/`AXF_PS_Participante` in the SAME transaction (app recreation orphans their `applicationVisibilities` otherwise — see AXF-159 PR history for the exact failure modes), and empty the manifest again immediately after confirming. |
