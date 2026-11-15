# Matching Policy — Axon Finance (mirror)

Canonical text: Confluence "Matching Policy — Axon Finance" (page 6488065), `policy_id: AXF-MATCHING`, `policy_version: 1.0.0`, approved 2026-08-26.

Implementation-relevant clauses, as applied by `ALT_CLS_MatchEvidence` (AXF-139):

1. **Advisory only.** Candidate generation never confirms, completes or selects. Confirmation is an explicit authorized human command (AXF-134 `confirm`).
2. **Evidence is independent facts** (amount, date, description, account, category, external identity, source identity, residual). No numeric weights, no composite score. Missing evidence is `UNKNOWN`, never zero or negative. Unauthorized evidence is `REDACTED` and cannot contribute to ordering.
3. **Ordering is presentation only**: verified external identity → exact source identity → canonical `typeRank` (persisted before virtual) → record identity. It is not a recommendation.
4. **Ties and incomplete evidence stay explicit** and select no winner; all candidates remain `CONSULTATIVE`.
5. **Text folding** (v1.0.0 implementation detail): lower case, whitespace, punctuation and Latin diacritics only; `CONTAINS` requires both normalized texts to have at least 3 characters. No fuzzy similarity.
6. **Change control**: any tolerance, weight, fuzzy feature or automatic selection needs a new policy version, calibration evidence and updated fixtures.

Applied by AXF-140 (`ALT_CLS_SourceLinkService`):

7. **No approved tolerance, weight or conclusion policy exists in v1.0.0**, so a non-zero remainder is
   reported as it is (`residualAfter`) and is never zeroed, settled or concluded automatically.
8. **Different currencies need material FX evidence** (§2). The candidate is shown with its original
   amount, available amount, currency, indicative conversion (AXF-92 vocabulary) and remainder kept
   apart; it stays `BLOCKED` and unlinkable because completion requires exact currency arithmetic
   (§3). A pair without a usable quote refuses confirmation with `MISSING_MATERIAL_FX` — the reason
   the user has to correct.
