<!-- PR body for: AXF-19: reconciled/base (head: feature/AXF-19-entry-wizard) -->

## Summary

Implements the guided entry wizard for manually recording an income/expense ("Lançamento
financeiro"), the first US to create the `FinancialTransaction` (FTX) object family in the
greenfield line (G1-3).

## Contract decision made at story open

Jira flagged one decision to close "at the opening of this story": which money/mutation
contract to follow, since `IMPLEMENTATION-CONTRACTS.md` (27/08) references retired mechanisms
(Household, `CommandExecution`, `AllocationSet`). Per `RECONCILIATION-CONTRACT.md` (line
122/124): the **Money algebra (§1) is kept**; the **mutation envelope (§4/§9) is superseded by
the closed G6-7** ("Version + idempotency key, CONFLICT on divergence, no CommandExecution").
Implemented accordingly — see `docs/implementation/AXF-19.md` for the full reasoning. Flagging
this explicitly in case the intended reading differs.

## Changes

- **`AXF_OBJ_FinancialTransaction__c`** (new, G1-3 shape): `Account` lookup required+Restrict,
  optional BankAccount/CreditCard (SetNull), `Direction` (DEBIT|CREDIT), `Magnitude` (Number —
  org has no native multi-currency, same call as AXF-87), `CurrencyIsoCode`, `PurchaseDate`/
  `DueDate`, `Status` (`CONFIRMED` only — lifecycle `ACTUAL_ONLY` for this US), `Version`,
  `ClientRequestId` (client-generated idempotency key, unique external id).
- **`AXF_CLS_FinancialEntryService`**: authority via AXF-3's authorized contexts (never trusts
  a client accountId), full validation, idempotent replay (same key+payload → `ALREADY`; same
  key+different payload → `CONFLICT`), funding source restricted to `AVAILABLE` (never
  `CUSTODY`, G5-5) sources of the same holder.
- **`AXF_CLS_CTRL_FinancialEntry`**: thin controller, sanitized errors.
- **`aXF_LWC_entryWizard`**: 4-step wizard (Context/Details/Source/Review), progress, Back/Next,
  final review, nothing persists before confirmation.
- **`AXF_PS_FinancialEntry`**: Create/Edit/Read on FTX (no Delete), added to both
  `AXF_PSG_GestorFinanceiro` and `AXF_PSG_Participante` — this is regular user data entry, not
  an `AXF_CanConfigure` admin action.

## Out of scope (own slices)

Category, installments/recurrence (AXF-20), linking to the imported source fact / reconciliation
(AXF-12, AXF-29/30/31), forecast/estimated states, edit/delete of an existing entry.

## Validation

- Jest: full worktree suite **94/94**; new `aXF_LWC_entryWizard` **5/5**.
- Apex: `AXF_CLS_FinancialEntryServiceTest` **9/9** on AXON_DEV.
- ESLint + Prettier clean. Deployed to `AXON_DEV` with `NoTestRun`. No AXON_PROD operation.

## Related work

https://axon-personal-finances.atlassian.net/browse/AXF-19 — predecessors AXF-3, AXF-86
(merged).
