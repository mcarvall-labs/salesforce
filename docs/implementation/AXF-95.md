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
  6/6; coverage: run service 94 %, read service 97 %, store 97 %, batch 84 %, controller 77 %.
- Jest `aXF_LWC_archiveExplorer` 4/4; ESLint clean.
- Spike evidence in `docs/implementation/AXF-102.md`.

## Deliberately out of scope

- Hot-copy removal (`COMPLETED` phase) — gated by AXF-79; `AllowHotRemoval` only changes the
  BLOCKED reason today.
- Backup provider selection; UAT/PROD enablement; archiving `AXF_OBJ_ReconciliationAllocation__c`
  or contract snapshots (they reference facts and are retained with the hot copy).
- Scheduled/automatic runs — runs are started explicitly per holder by a Gestor.
