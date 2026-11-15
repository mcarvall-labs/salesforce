# AXF-95 — Transaction archive (Big Object) with read-only consultation

Implements AD-39 / D-83 / D-84 after the AXF-102 PASS (`docs/implementation/AXF-102.md`).

## Components

| Component                                                                                 | Role                                                                                                                                                         |
| ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `AXF_OBJ_TransactionArchive__b`                                                           | Immutable archive rows; index `AccountKey ASC, BookingDate DESC, ArchiveKey ASC`.                                                                            |
| `AXF_OBJ_ArchiveRun__c` + `AXF_TRG_ArchiveRun`                                            | Private, service-only checkpoint per (family, holder, policy version, hot-window start). No delete.                                                          |
| `AXF_CMT_ArchivePolicy__mdt.Default`                                                      | `HotWindowMonths` 24, `BatchSize` 200, `Enabled` true, `AllowHotRemoval` false, `archive-policy@1.0.0`.                                                      |
| `ALT_CLS_ArchivePolicy`                                                                   | Resolves the policy; missing/disabled/invalid → `POLICY_*` (blocks, never assumes a window).                                                                 |
| `ALT_CLS_ArchiveStore`                                                                    | Only gateway to the big object (`without sharing`); index-bounded reads, `insertImmediate` upserts.                                                          |
| `ALT_CLS_ArchiveRunService` + `AXF_CLS_ArchiveRunBatch`                                   | Batch archiving per family with checkpoint-after-write, resume from the watermark, parity verification.                                                      |
| `ALT_CLS_ArchiveReadService`                                                              | Read-only, authorized, keyset-paginated consultation; never rehydrates.                                                                                      |
| `AXF_CLS_CTRL_ArchiveExplorer` + `aXF_LWC_archiveExplorer` + tab `AXF_CT_ArchiveExplorer` | UI: holder + period before the hot window, async read with its own state, "Arquivado" badge, read-only rows, run list, "Arquivar agora" (with confirmation). |
| Custom permissions                                                                        | `AXF_CanReadArchive`, `AXF_CanArchiveTransactions` (granted by `AXF_PS_GestorFinanceiro`).                                                                   |

## Acceptance criteria

1. **ArchiveRun** — facts dated before `hotWindowStart` (first day of the current month minus
   `HotWindowMonths`) are mapped and upserted by `ArchiveKey`; the checkpoint moves only after the
   chunk is written; a failure sets `FAILED` with a safe reason and `start()` resumes from the
   watermark day (re-reading that day is harmless: same keys). `verify()` re-reads the archive
   (bounded, `VERIFY_LIMIT` 2000) recomputing count/credit/debit per currency and compares with an
   independent aggregate of the hot copy → `PARITY_MISMATCH` fails the run. **The hot copy is not
   removed**: runs end `HOT_RETAINED` with `HotRemoval = BLOCKED:HOT_REMOVAL_NOT_AUTHORIZED`
   (or `BLOCKED:RECOVERY_GATE_OPEN`). Removal stays conditioned on the AXF-79 recovery gate and
   explicit authorization.
2. **Consultation** — `read()` accepts one holder and a period; the upper bound is clamped to the
   day before the hot window; results come newest first with an `archived` flag; the LWC renders
   the "Arquivado" badge, no inline editing, and a "Carregar mais" cursor. Nothing is written to
   hot objects.
3. **Limits** — every archive query filters the full index prefix and carries `LIMIT ≤ 200`;
   pagination uses (date, key) keyset (same-day remainder, then older days); no aggregate or
   unbounded scan; batch scope is a `QueryLocator` on the hot object filtered by holder and date.
4. **Policy** — changing `AXF_APL_NUM_HotWindowMonths__c` moves the window on the next run/read
   without a code deploy (`ALT_CLS_ArchivePolicy.resolve`).

## Validation

- AXON_DEV deploy `0Afaj00000kMbrHCAS` (160 components) with `ALT_CLS_ArchiveRunServiceTest`
  7/7 (deploy `0Afaj00000kNNJBCA4` after review); coverage: run service 95 %, read service 99 %, store 90 %, batch 76 %, controller 81 %.
- Jest `aXF_LWC_archiveExplorer` 5/5; ESLint clean.
- Spike evidence in `docs/implementation/AXF-102.md`.

## Code review hardening (BMAD, 2026-09-15)

- `contentHash` scale/timezone independent (real verification would otherwise fail).
- `start()` refuses a run whose batch is still executing (`AXF_ARR_TXT_JobId__c` +
  `AsyncApexJob`) or a sibling active run of the same family/holder (`RUN_IN_PROGRESS`), and tells
  a second archivist that the checkpoint belongs to someone else (`RUN_OWNED_BY_OTHER`).
- A `PARITY_MISMATCH` resume re-scans the whole window; `verify()` recomputes the authoritative
  counts and a chunking-independent run hash (sorted verified keys); sampled verification
  (`VERIFY_LIMIT` 10 000) marks `HotRemoval = BLOCKED:VERIFY_SAMPLED`.
- Batch failures keep the typed reason, abort the job and never throw while recording; a failure
  in `start()` is recorded as `START_FAILED`; per-row `insertImmediate` failures stop the checkpoint.
- Read cursor must lie inside the requested window; `fromDate` floored at 1700-01-01; policy
  months capped at 1200; `read(runId)` returns `RUN_NOT_ACCESSIBLE` instead of a raw exception.
- Snapshot keeps only the fact's own fields and marks truncation explicitly.
- LWC: holder search, per-family start errors in the runs section (other families still start),
  double-start guard, retry refreshes the context wire, forbidden/policy-blocked states, holder
  change discards in-flight results, Escape/focus on the confirmation dialog, date pickers capped at
  the day before the hot window, run reason column.

## Deliberately out of scope

- Hot-copy removal (`COMPLETED` phase) — gated by AXF-79; `AllowHotRemoval` only changes the
  BLOCKED reason today.
- Backup provider selection; UAT/PROD enablement; archiving `AXF_OBJ_ReconciliationAllocation__c`
  or contract snapshots (they reference facts and are retained with the hot copy).
- Scheduled/automatic runs — runs are started explicitly per holder by a Gestor.
