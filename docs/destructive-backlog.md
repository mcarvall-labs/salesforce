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

### AXON_UAT status (checked 2026-09-17)

No drift: every class in `uat` branch is deployed, and the only untracked classes in
the org are `AXF_CLS_ScratchDebugTest` (likely a manual scratch artifact, low risk)
and the same 4 `devedapp__` managed-package classes above. No destructive action
needed for UAT.

### AXON_DEV status

Not yet checked. Pending in AXF-161.

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

## Status: in review — Axon Finance app tabs back to production parity (26/09/2026)

Branch `fix/axf-151-app-tabs-prod-parity` (review decision in `AXF_Apps_Tabs.xlsx`, rows 1-3:
"Corrigir — igual produção", option B confirmed by the owner on 26/09/2026). The LWC tabs
`AXF_CT_BankStatement`/`AXF_CT_CardStatement` (AXF-151/AXF-152) are replaced by the standard
object tabs of `AXF_OBJ_BankAccount__c`/`AXF_OBJ_CreditCard__c` with the production record
pages, page layouts and `View_All` list views (production fields mapped to their greenfield
equivalents; production-only fields without an equivalent recreated). The statement LWCs now
live on the record pages, so only these are deleted through `manifest/destructiveChangesPost.xml`:

```
CustomTab: AXF_CT_BankStatement, AXF_CT_CardStatement
ListView: AXF_OBJ_BankAccount__c.All, AXF_OBJ_CreditCard__c.All (replaced by View_All)
```

Never deployed to AXON_PROD (not in `main`), so the PROD deletion is a warning-only no-op.
Companion PermissionSet-only PR `fix/axf-151-app-tabs-prod-parity-permissionsets` moves the
`tabSettings` to the object tabs and grants FLS on the recreated fields; merge it after this
one. Empty the manifest once applied in DEV/UAT.
