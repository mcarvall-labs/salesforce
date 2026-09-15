---
title: "Product Brief: Axon Finance"
status: approved
created: 2026-08-17
updated: 2026-08-20
approved: 2026-08-20
---

# Product Brief: Axon Finance

## Executive Summary

Axon Finance is an existing Salesforce-native financial operating system for a household and its related companies. It combines actual bank and credit-card activity with planned income, expenses, obligations, goals, and investments to answer five questions: how much can be spent, how much can be invested, what must be paid, what will be received, and whether upcoming obligations remain affordable.

Each adopting household installs Axon in its own Salesforce Developer organization, isolating its data from other households. Existing functionality is the protected baseline and must be reused unless a documented decision explains the compatibility impact, migration, and regression risk.

## Product Outcomes and Decision Rules

Axon succeeds when an authorized user can quickly answer, in priority order:

1. How much can I safely spend?
2. How much can I safely invest?
3. What must I pay next, including overdue obligations?
4. How much am I expected to receive?
5. Can I meet my obligations over the selected horizon?

These are decision indicators, not disconnected totals:

- **Spending capacity** = available balance + scenario-eligible income - planned bills and commitments - safety reserve - amounts reserved for goals. A negative result is displayed as zero capacity plus a separate forecast deficit.
- **Investment capacity** = remaining spending capacity - planned optional spending - scheduled investment contributions. Only surplus that remains available throughout the selected horizon without compromising obligations, reserve, or goals qualifies. A negative result is displayed as zero capacity plus the forecast deficit.
- **Revenue scenarios** use full amounts without percentage weighting: conservative includes confirmed income; intermediate adds probable income; optimistic adds uncertain income.
- **Data confidence** is reduced when an account is stale. Each account has a configurable freshness threshold and exposes its last successful update.

## Users, Entities, and Access

- One installation serves one household containing multiple people and one or more related companies.
- Every person and company is a distinct financial entity. Accounts, cards, transactions, plans, forecasts, reserves, goals, and documents retain entity ownership or attribution in both individual and consolidated views.
- Account ownership and transaction attribution are separate, allowing a mixed-use account while assigning each transaction wholly to one entity. Splitting a transaction across entities is outside the initial scope.
- Internal transfers are linked on both sides and eliminated from consolidated income and expense totals.
- Michel is the administrator and may manage all entities. Gisele has a separate login and sees her authorized personal, company, and shared household records. On authorized shared expenses she may view, create, edit, categorize, and mark paid; deletion remains administrator-only.
- Phase 1 must preserve the entity and access boundaries in its data and service contracts even where the full sharing experience is delivered in Phase 3. No decision indicator may expose an entity the active user cannot access.

## Forecasting and Financial Rules

- Selectable horizons are 3, 6, 9, 12, 15, 18, 21, and 24 months; selecting a shorter horizon does not truncate longer-lived obligations.
- The safety reserve is configurable as a fixed amount, a percentage of income, or months of expenses.
- Expense flexibility uses mandatory, essential-but-adjustable, and optional/deferrable levels. Axon identifies review targets during a shortfall but never changes plans automatically.
- Income rules belong to their source or contract: fixed, manually variable, hourly, or another documented calculation. Confidence is independent of the amount model.
- Income and expenses support one-time, installment, PRICE/SAC financing, consortium, and flexible recurrence, including weekly, monthly, bimonthly, quarterly, and semiannual schedules.
- Financial events use their effective local date and the account or contract time zone; working-day calculations use the contract calendar. Original currency and amount are immutable. Consolidated views convert through a stored, dated rate and disclose the reporting currency, rate source, rate date, and any missing-rate exclusion.
- Forecast and actual records remain distinct and traceably linked. Reconciliation confirms, adjusts, or leaves a forecast open; it never silently overwrites the original plan. Partial settlements preserve the remaining balance, and manual overrides are auditable.

## Protected Baseline and Development Sequence

Repository and historical delivery evidence cover Open Finance synchronization through Pluggy, accounts, cards, transactions, reconciliation, cash-flow planning, income and expenses, investments, loans, dashboards, alerts, quick entry, recurrence, installments, financing, and consortiums. Each capability must be verified against current code, but none may be discarded or rebuilt without cause.

Development priority is:

1. **Forecasting and decision indicators.** Stabilize planned cash flow and the five core answers. Reuse working Open Finance imports; manual maintenance of `Contabilizei.bank` is acceptable temporarily.
2. **Transaction import and reconciliation.** Add bank-specific CSV import, reconciliation, transaction-to-plan conversion, and layered duplicate prevention.
3. **Household, company, and permissions.** Complete entities, mixed-use accounts, internal transfers, selective consolidation, and secure shared-family workflows.
4. **Timesheets, billing, email, and documents.** Deliver contract calendars, hours, client-specific packages, OneDrive archiving, receipt reconciliation, and accountant handoff.

Priority does not authorize removal of working later-phase functionality.

## Scope, Quality, and Sources of Truth

- Jira project `AXF` is the execution source of truth. Confluence space `AXF` is the product and decision-documentation source of truth. GitHub remains the code and delivery-traceability system; historical issues and pull requests are evidence to assess before migration.
- Open Finance keys enforce deterministic idempotency. Similar manual or file-imported records produce an advisory comparison; the user may open the candidate, cancel, or proceed with an auditable confirmation. Axon never deletes or merges records based only on similarity.
- Every financial mutation and override must be attributable to a user and timestamp. Entity access, sharing, CRUD/FLS enforcement, least privilege, and household isolation are release gates.
- Decision indicators must be reproducible from versioned inputs, explain included and excluded amounts, and retain traceability from summary to source record.
- Imports must be previewed and validated before commit, be atomic per batch, retain source and outcome, and support safe retry without duplicating committed records.
- Failures must be visible and recoverable without corrupting confirmed financial data. Backup confirmation is required before Salesforce-held client files may be deleted.

Detailed access rules, import states, reconciliation behavior, billing lifecycle, and reviewed evidence are preserved in `operational-addendum.md`.
