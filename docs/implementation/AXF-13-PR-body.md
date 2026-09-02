<!-- PR: AXF-13: reconciled/base -->

## Related work

- Jira: https://axon-personal-finances.atlassian.net/browse/AXF-13 — *Garantir identidade externa Pluggy em reprocessamentos e reconexões* (Epic AXF-10)
- Synchronized with `reconciled/base` after AXF-11 (PR #44) was finalized; uses `AXF_OBJ_PluggyConnection__c`.
- Local record: `docs/implementation/AXF-13.md`

## Contract

G6 definition phase closed (30/08). Follows `ARCHITECTURE-SPINE.md` §"Fechamento G6" and the 30/08 Jira note (comment 10202). The simplified G6 form (no mandatory `SourceIdentityAlias` with token machinery) prevails over the older `IMPLEMENTATION-CONTRACTS.md` shape, per AC4.

## What this delivers

On the greenfield base only `AXF_OBJ_PluggyConnection__c` exists. The transaction/account/card fact objects are created by the stories that consume them (AXF-12, AXF-84, AXF-14/15, cards cluster), each applying **this** contract. AXF-13 delivers the reusable, deterministic primitives + the reconnection-equivalence mechanism, proven from an empty base.

| Area | Component |
|---|---|
| Canonical framing + hash | `AXF_CLS_IdentityFraming` — length-prefixed UTF-8 `frame()`, `sha256Hex()`, `key()`. Delimiter injection inert; order matters; `null` ≠ empty; pure/deterministic |
| Versioned description normalization (D-62) | `AXF_CLS_TextNormalization` — `normalize()` + `POLICY_VERSION = norm-v1`, idempotent |
| Fact identity (G6-1) | `AXF_CLS_PluggyFactIdentity` — provider UUID verbatim, or `fallback()` = `sha256(frame(fbk-v1, parentExternalId, ISO date, amount(2 dp), norm-version, normalized desc))`. **Parent id inside the hash** (D-61) → a locally-unique id never collides across parents. Exactly one key produced |
| Reconnection equivalence (AC3/AC4/AC5) | `AXF_OBJ_SourceEquivalence__c` (OWD Private) + `AXF_CLS_SourceEquivalenceService` — `record()` → PENDING (**similarity never auto-verifies**); `verify()`/`reject()` gated by `AXF_CanConfigure`; **one VERIFIED per scope** → `CONFLICT`; idempotent on `(connection, transientHash)`; alias → stable connection only (**no chains**); `resolveStableConnection()` |
| Access without revealing existence (AC7) | `WITH USER_MODE` queries + OWD Private; "não encontrada" covers both missing access and a genuine miss |

## Findings (AC1 / Jira comment 10202)

- Legacy `AXF_BAT_/CCT_EXI_PluggyTransactionId__c`: Text(255) `unique` **global**, `externalId`, `caseSensitive=false`, **`required=true`**. UUID → global scope OK, but `required=true` conflicts with the "exactly one of id/fallback" rule → must become non-required + Validation Rule when AXF-12 creates the object. No `FallbackKey` / `NormalizedDescription` in the legacy schema.
- **`AXF_CCI_EXT_ExternalId__c` = `{LastFourDigits}_{YYYY-MM}` → collides across cards/banks (D-61).** Must become `{CreditCardExternalId}_{YYYY-MM}` (or include the bank) before any build relies on it for invoice↔transaction association. `AXF_CCI_EXI_PluggyInvoiceId__c` stays the preferred key.

## Out of scope

Reconciliation matching / smart dedup (Deferred); physical identity migration = **design only** (§4 of the doc, execution = G9); per-fact-object identity fields (AXF-12/84); manual/CSV identity contract (AXF-15).

## Validation

Check-only validation against `AXON_DEV` passed in job `0Afaj00000ipUqkCAE`: 26/26 specified Apex tests green. Coverage: `AXF_CLS_IdentityFraming` 94%, `AXF_CLS_PluggyFactIdentity` 97%, `AXF_CLS_TextNormalization` 97%, and `AXF_CLS_SourceEquivalenceService` 99%. No persistent feature-branch deployment was made during the restack.
