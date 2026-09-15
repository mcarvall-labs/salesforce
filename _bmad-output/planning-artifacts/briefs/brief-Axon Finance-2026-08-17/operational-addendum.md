---
title: "Axon Finance Product Brief - Operational Addendum"
status: approved
created: 2026-08-18
updated: 2026-08-20
approved: 2026-08-20
---

# Operational Addendum

This addendum preserves operational detail that constrains downstream PRD and architecture work without expanding the main product brief.

## Entity and Access Matrix

| Capability | Administrator | Authorized member | Unauthorized member |
| --- | --- | --- | --- |
| Own personal/company records | Full access | Full access to assigned entities | No access |
| Authorized shared household expenses | Full access | View, create, edit amount/due date/description/category, and mark paid | No access |
| Delete shared household expenses | Allowed | Not allowed | Not allowed |
| Household or cross-entity consolidation | Full access | Only explicitly authorized entities and shared records | No access |
| Source attribution in consolidated views | Always visible | Always visible for accessible records | No access |

Salesforce roles, sharing, Permission Sets, Permission Set Groups, user-mode operations, and explicit CRUD/FLS enforcement are candidate mechanisms; architecture selects the package-compatible implementation. Phase 1 indicators must already accept an entity scope and enforce the active user's accessible record set so later sharing work does not require a financial-model rewrite.

## Dates, Calendars, and Currencies

- Store the original financial event date and, when available, source timestamp and source time zone. Date-only bank events retain the bank-provided local date.
- Contract forecasts use the contract time zone and its national, regional/state, municipal/local, and custom holiday calendar. Vacation and other non-working-day overrides are explicit.
- Keep original currency and amount immutable. Every conversion stores the reporting currency, rate, rate date, rate source, and rounding result.
- Use the event-date rate for realized transactions and the configured planning rate for forecasts. A forecast-to-actual reconciliation records both rates rather than replacing the forecast rate.
- If a required rate is absent, exclude that amount from consolidated indicators, disclose the exclusion, and lower confidence; never assume parity or silently reuse an undated rate.
- Round display values to the currency's supported precision while retaining calculation precision sufficient to reproduce totals.

## Transaction Acquisition and Import Lifecycle

Pluggy/Open Finance automatic imports remain protected. Accounts without integration may be manual and accept the bank's original CSV; PDF statements are supporting evidence.

Each bank format has an isolated maintained parser. The initial `Contabilizei.bank` company-account CSV is UTF-8 and contains date, category, transaction type, description, incoming amount, outgoing amount, and daily balance. The parser handles Brazilian numeric formatting and non-breaking spaces.

Each import follows one explicit lifecycle:

1. **Upload and identify:** retain source hash, filename, account, parser version, user, and batch ID.
2. **Parse and validate:** reject unsupported structure; report row-level errors without committing financial records.
3. **Preview:** show normalized rows, totals, date range, deterministic duplicates, and similarity candidates.
4. **Confirm:** require the user to resolve blocking errors and acknowledge advisory candidates.
5. **Commit atomically:** create the accepted records and audit decisions as one batch; a failed commit creates no partial financial result.
6. **Reconcile and report:** expose created, matched, skipped, overridden, and failed counts with links to candidates and records.
7. **Retry safely:** reuse the source hash and batch history so repeated or overlapping uploads do not duplicate committed records.

Identical-looking same-day rows may both be legitimate where no external transaction ID exists. Strong external keys block deterministic duplicates; similarity remains advisory and any proceed-anyway action is auditable.

## Forecast-to-Actual Reconciliation

- Forecast and actual records are separate, linked records with independent amounts, currencies, dates, confidence, and provenance.
- A match may confirm the forecast, record a variance, partially settle it, or mark it unmatched. Partial settlement retains the open remainder.
- One actual movement may be allocated only according to downstream reconciliation rules; initial entity attribution remains whole and does not imply cross-entity allocation.
- Reconciliation never changes the original forecast silently. Corrections create an auditable revision or explicit override with user, timestamp, reason, and before/after values.
- Imported bank or card transactions can create traceably linked one-time, recurring, installment, financing, consortium, fixed, or variable revenue/expense definitions.
- Foreign-currency receipts may be matched to invoices. Axon derives VET from the foreign invoice amount and actual BRL credit, presents the calculation, and requires confirmation.

## Contract-Based Revenue

- Example Portugal contract: EUR 28/hour, 8 hours per working day.
- Example Brazil contract: BRL 150/hour, 4 hours per working day.
- Each contract selects its work calendar and supports vacation/non-working-day overrides.
- Monthly rent is a near-fixed source that can include temporary fees or deductions.
- Fixed/variable amount and confirmed/probable/uncertain confidence are independent attributes.

## Client Document Lifecycle

The lifecycle is contract-configurable and preserves every generated version:

1. Calculate the service period from the approved contract calendar and forecast or actual hours.
2. Generate client-specific timesheet and invoice drafts from versioned templates; numbering and service periods come from billing events, never stale templates.
3. Review and approve the package in Salesforce; externally produced required documents may be attached before sending.
4. Send through the contract-specific email template and record recipients, subject, attachments, timestamp, and delivery outcome.
5. Reconcile receipt against the bank movement. For the Portugal workflow, the accountant document then adds actual credit date, BRL amount, and VET while retaining EUR hours, rate, and total.
6. Archive the complete package under `OneDrive/PJ/client/year/month`, record a durable link and backup confirmation, then permit Salesforce file deletion according to retention policy.

For MEO/Devoteam, the package is due on day 10 and contains the current-month invoice and timesheet based on forecast working hours plus the prior-month NFSe. Rare hour differences are corrected manually in the applicable Salesforce timesheet; no automated next-month adjustment is required. The supplied Portugal PDF layouts and email content are client-required. July 2026 was 184 hours x EUR 28 = EUR 5,152; August was 168 hours x EUR 28 = EUR 4,704.

Future Brazilian clients may require a time report and pre-invoice approval before NF issuance, using separate templates and attachment rules.

## Operational Quality Gates

- **Security and privacy:** household isolation, least privilege, record-level sharing, CRUD/FLS enforcement, and no indicator leakage across unauthorized entities.
- **Integrity:** idempotent integrated imports, atomic file batches, immutable source facts, explicit overrides, and no silent plan mutation.
- **Explainability:** every indicator can enumerate its inputs, scenario, horizon, exclusions, conversion rates, freshness, and source records.
- **Recoverability:** visible errors, retryable imports and document delivery, retained batch outcomes, and backup confirmation before file deletion.
- **Auditability:** user and timestamp for mutations, reconciliations, duplicate overrides, approvals, sends, archives, and deletions.
- **Compatibility:** protected baseline behavior requires regression assessment before replacement or material change.

## Evidence Reviewed

- Salesforce repository `mcarvall-labs/salesforce`, including historical issues, pull requests, and commits.
- Jira project `AXF`, the canonical execution backlog.
- Confluence space `AXF`, the canonical product-documentation space.
- Supplied July/August timesheets and client invoices, May-July accountant documents, August email `.msg`, spreadsheet calculation model, and `Contabilizei.bank` CSV.
