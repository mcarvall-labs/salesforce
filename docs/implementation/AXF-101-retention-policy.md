# AXF-101 domain retention foundation

`ALT_CLS_RetentionPolicy.evaluate` computes retention eligibility without reading business records, changing data, or granting purge authority. Resolution and dismissal retain all seven typed ReviewItem Prior fields. Final-row protections remain in force; purge orchestration and consumer integrations require separate implementation.

## Administrator configuration

No policy records are shipped. Missing, disabled, invalid, or ambiguous configuration blocks eligibility. Create a policy only after its domain, trigger, retention period, and version are approved; there is no default period or cross-domain inheritance.

Canonical Custom Metadata type: `AXF_CMT_RetentionPolicy__mdt`.

| Field                          | Type                    | Meaning                                     |
| ------------------------------ | ----------------------- | ------------------------------------------- |
| `AXF_RPT_TXT_Domain__c`        | Text 255                | Exact domain key                            |
| `AXF_RPT_TXT_PurgeTrigger__c`  | Text 255                | Exact triggering event                      |
| `AXF_RPT_NUM_RetentionDays__c` | Number 18,0             | Explicit positive integral elapsed UTC days |
| `AXF_RPT_BOL_Enabled__c`       | Checkbox, default false | Explicit enablement                         |
| `AXF_RPT_TXT_Version__c`       | Text 255                | Explicit nonblank policy version            |

For ReviewItem prior evidence, use exactly `review.prior` and `REVIEW_FINALIZED`. Configure exactly one record per domain: disabled duplicates also cause ambiguity. Domain/trigger comparison is case-sensitive and does not trim values. No enabled example or business retention period is supplied. Runtime rejects missing/nonpositive/fractional days, unusable ranges, and date overflow. Metadata Number scale 0 means administrators must supply approved integral values before saving.

## Trusted consumer contract

Consumers authorize their caller and load current business state server-side. Supply a trusted server `evaluatedAt`, the explicit `domain` and `purgeTrigger`, the triggering timestamp, and known Boolean values for legal hold, active dependencies, open review, and unresolved outcomes. Null safety flags fail closed. For `review.prior`, `triggerAt` is the stored `AXF_RVI_DT_ResolvedAt__c`; `reviewState` must be `RESOLVED` or `DISMISSED`. Never use CreatedDate as the retention start.

Results retain input order. `KEEP` means the explicit window has not elapsed; `ELIGIBLE` begins exactly at the UTC deadline. Both include `dueAt` and a receipt. `BLOCKED` has `eligible=false`, a stable safe reason code, and null due time/receipt. No status authorizes deletion.

Persist the first receipt in trusted server storage. For subsequent evaluation, reload it, set `replay=true`, and pass it as `originalReceipt`, while refreshing all current safety inputs. Do not accept a client-generated receipt or treat a replay as a new evaluation. Identity is namespace-qualified DeveloperName. The SHA-256 fingerprint covers identity, version, domain, trigger, enabled state, and days. Changed contents (even with unchanged version), identity, receipt domain/trigger/timestamp, or unavailable policy block replay. An approved policy change therefore needs explicit consumer reconciliation; it never silently shortens existing retention. Advance the version for approved changes, but version alone is not the change detector.

## Validation evidence

Portuguese metadata translations packaged successfully. Tests use policy fixtures for absent/invalid policies; the real-loader test compares the current metadata snapshot and remains valid after administrator configuration. A source-file audit separately verifies that no retention policy records ship.

Review patch validation: check-only `0Afaj00000jemIYCAY` succeeded with 26 tests, zero failures, and 129/130 evaluator lines covered (99.23%). The suite now includes a mixed batch with positional receipt checks, pending receipt replay through its original expiry, enabled/disabled duplicate ambiguity, and all seven retained Prior values for both final states. ResolvedAt is bounded by timestamps captured immediately before/after the resolver call at the persisted second precision. Focused Prettier and `git diff --check` passed. Final PMD: zero severity 1/2; 47 moderate and 28 low convention/complexity warnings, with no suppressions. Source audit found zero retention policy records. Raw outputs remain local as `axf-101-review-validation.json` and `axf-101-review-analyzer.json`.
