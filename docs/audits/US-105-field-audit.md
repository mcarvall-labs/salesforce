# US-105 — Cash Flow and Installment Group field audit

Audit date: 2026-07-31
Confirmed target org: `AxonFinance` (`michel.lopes@axonfinance.com`)
Scope: every custom field returned by describe for `AXF_OBJ_CashFlow__c` and `AXF_OBJ_InstallmentGroup__c`.

## Outcome

- 36 custom fields inventoried: 22 Cash Flow and 14 Installment Group.
- 35 fields are retained because they have an active business, code, metadata, or integrity role.
- `AXF_CF_CUR_EstimatedValue__c` is **Deprecate First**. `AXF_CF_CUR_Value__c` plus `AXF_CF_CHK_IsEstimated__c` supersedes it, but its permission-set reference must be removed and a longer observation period completed first.
- No field meets the safe definition of **Destructive Candidate**. The proposed destructive manifest is intentionally empty.
- No metadata or data was deleted and no destructive deployment was executed.

The org currently contains one Cash Flow record and no Installment Group records. Population counts below are therefore directional only and cannot prove that a field is safe to delete.

## Evidence method

The audit searched exact API-name references across Apex, triggers, LWC, Flow, validation rules, field formulas, layouts, compact layouts, record types, list views, reports, dashboards, translations, permission sets, integration/configuration files, scripts, and deployment manifests. Org describe supplied the authoritative field inventory; `FIELDS(ALL)` read-only queries supplied population evidence. No relevant report/dashboard or Flow reference was found in source.

Legend: `A` Apex/trigger, `U` LWC/UI, `M` object metadata/layout/list view/validation, `P` permission set, `T` translation. “Refs” excludes the field's own definition where it exists.

## Cash Flow evidence matrix

| Field | Type | Refs / evidence | Populated | Recommendation | Rationale |
|---|---|---:|---:|---|---|
| AXF_CF_CHK_IsEstimated__c | Checkbox | 5 · A,P | 0/1 | Keep | Distinguishes forecast values in recurring, SAC, and consortium schedules. |
| AXF_CF_CUR_EstimatedValue__c | Currency | 1 · P | 0/1 | Deprecate First | Superseded by Value + Is Estimated; permission dependency remains. |
| AXF_CF_CUR_PaidValue__c | Currency | 5 · A,P | 0/1 | Keep | Preserves actual paid amount independently from forecast/base value. |
| AXF_CF_CUR_Value__c | Currency | 21 · A,U,M | 1/1 | Keep | Primary amount used throughout creation, settlement, display, and aggregation. |
| AXF_CF_DAT_DueDate__c | Date | 18 · A,U,M | 1/1 | Keep | Drives status, monthly views, forecasting, and installment chronology. |
| AXF_CF_DAT_PaymentDate__c | Date | 8 · A,M | 0/1 | Keep | Required settlement history and late-payment classification. |
| AXF_CF_DAT_PurchaseDate__c | Date | 6 · A,M | 1/1 | Keep | Preserves transaction origin date and seeds generated entries. |
| AXF_CF_LKP_Account__c | Lookup | 7 · A,M | 1/1 | Keep | Ownership and account-level reporting relationship. |
| AXF_CF_LKP_BankAccount__c | Lookup | 5 · A,P | 1/1 | Keep | Payment-source relationship used by creation and forecasts. |
| AXF_CF_LKP_BankAccountTransaction__c | Lookup | 11 · A,U,M,P | 0/1 | Keep | Bank reconciliation link and integrity enforcement. |
| AXF_CF_LKP_Category__c | Lookup | 9 · A,M,P | 1/1 | Keep | Classification, filtering, and copied installment context. |
| AXF_CF_LKP_CreditCard__c | Lookup | 5 · A,P | 0/1 | Keep | Card payment-source relationship. |
| AXF_CF_LKP_CreditCardTransaction__c | Lookup | 11 · A,U,M,P | 0/1 | Keep | Card reconciliation link and integrity enforcement. |
| AXF_CF_LKP_InstallmentGroup__c | Lookup | 7 · A,M | 0/1 | Keep | Parent relationship for schedule maintenance and aggregate totals. |
| AXF_CF_NUM_CurrentInstallment__c | Number | 7 · A,M | 1/1 | Keep | Sequence and idempotency key for generated schedules. |
| AXF_CF_NUM_TotalInstallments__c | Number | 7 · A,M | 1/1 | Keep | Contract cap and installment display context. |
| AXF_CF_PKL_PaymentMethod__c | Picklist | 9 · A,U,M,P | 1/1 | Keep | Controls source validation and payment handling. |
| AXF_CF_PKL_PaymentMode__c | Picklist | 9 · A,M,P | 1/1 | Keep | Selects one-time, recurring, financing, SAC, or consortium behavior. |
| AXF_CF_PKL_ProvisioningStrategy__c | Picklist | 6 · A,M,P | 1/1 | Keep | Determines variable recurring forecast calculation. |
| AXF_CF_PKL_ReconciliationStatus__c | Picklist | 17 · A,M,P,T | 0/1 | Keep | Actively enforced with mutually exclusive reconciliation lookups; source is synchronized with org. |
| AXF_CF_PKL_RecurringType__c | Picklist | 6 · A,M,P | 1/1 | Keep | Distinguishes fixed and variable recurring schedules. |
| AXF_CF_PKL_Status__c | Picklist | 18 · A,U,M | 1/1 | Keep | Core lifecycle, views, settlement, and group aggregation. |

## Installment Group evidence matrix

| Field | Type | Refs / evidence | Populated | Recommendation | Rationale |
|---|---|---:|---:|---|---|
| AXF_IG_CUR_InstallmentAmount__c | Currency | 6 · A,U,M | 0/0 | Keep | Base installment and future-adjustment value. |
| AXF_IG_CUR_TotalAmount__c | Currency | 3 · A,M | 0/0 | Keep | Contract total initialized during schedule creation and shown in summaries. |
| AXF_IG_CUR_TotalPaidAmount__c | Currency | 3 · A,M | 0/0 | Keep | Trigger-maintained paid aggregate. |
| AXF_IG_CUR_TotalRemainingAmount__c | Currency | 3 · A,M | 0/0 | Keep | Trigger-maintained remaining aggregate. |
| AXF_IG_DAT_AdjustmentAnniversary__c | Date | 7 · A,U,M,P | 0/0 | Keep | Eligibility boundary for consortium adjustments. |
| AXF_IG_DAT_FirstDueDate__c | Date | 4 · A,M | 0/0 | Keep | Deterministic source for generated installment due dates. |
| AXF_IG_DAT_LastAdjustmentDate__c | Date | 3 · M,P,T | 0/0 | Keep | Reserved idempotency/history marker and constrained by consortium validation. |
| AXF_IG_NUM_OverdueInstallmentsCount__c | Number | 3 · A,M | 0/0 | Keep | Trigger-maintained overdue aggregate. |
| AXF_IG_NUM_PaidInstallmentsCount__c | Number | 3 · A,M | 0/0 | Keep | Trigger-maintained paid count. |
| AXF_IG_NUM_PendingInstallmentsCount__c | Number | 3 · A,M | 0/0 | Keep | Trigger-maintained pending count. |
| AXF_IG_NUM_TotalInstallments__c | Number | 5 · A,M | 0/0 | Keep | Contract cap for financing and consortium schedules. |
| AXF_IG_PCT_MonthlyAdjustmentRate__c | Percent | 5 · A,M,P | 0/0 | Keep | SAC forecast rate with validation constraints. |
| AXF_IG_PKL_FinancingType__c | Picklist | 6 · A,M,P | 0/0 | Keep | Differentiates financing calculation model. |
| AXF_IG_PKL_GroupType__c | Picklist | 9 · A,U,M,P | 0/0 | Keep | Dispatch key for recurring, financing, SAC, and consortium behavior. |

## Deprecation plan: Estimated Value

- Replacement: `AXF_CF_CUR_Value__c` stores the forecast or actual amount; `AXF_CF_CHK_IsEstimated__c` states whether it is estimated.
- Backfill: before any later destructive story, copy non-null legacy Estimated Value into Value only where Value is null, and set Is Estimated to true. Produce before/after counts and exceptions.
- Dependency removal: remove field-level access from `AXF_PS_User`, verify no subscriber/integration/report dependency outside source, hide the field, and observe at least one release cycle.
- Retention risk: historical integrations may still write the legacy field even though current source does not read it.
- Rollback: retain field metadata and data throughout deprecation; restore permission/layout visibility if monitoring finds a consumer.
- Destructive eligibility gate: zero population after backfill, zero repository and org dependencies, explicit owner approval, backup/export evidence, and a separate authorized destructive-change story.

## Review and rollback controls

For every future candidate: export field data keyed by record Id, capture metadata and dependency snapshots, remove consumers before metadata, validate in a non-production org, retain the export for the agreed retention period, and require explicit destructive-deploy authorization. The present audit authorizes none of those mutations.
