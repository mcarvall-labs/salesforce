<!-- PR body for: AXF-8: reconciled/base  (head: feature/AXF-8-revoke-derived-access) -->

## Summary

Completes AXF-8 on top of the AXF-83 server un-grant: client-side convergence across the
Axon-controlled context surface **and** the administrative view of the effective
revocation/grant state (AC5).

## Changes

- **`aXF_LWC_contextBar`** — clears the selected context and derived client state before
  authorization revalidation; revalidates on reconnect, window focus, visible-tab return and
  explicit retry; publishes an `AUTHORIZATION_REVALIDATION` reason (new `changeReason` field on
  `AXF_ContextChanged__c`) for consumers to discard stale data before refetching. No client
  state or TTL is used as authorization; no queued mutation replay.
- **`aXF_LWC_companyResponsibleAccess`** (new) — Business Account admin view. One row per
  responsible showing the **effective** status (`GRANTED` / `RELATIONSHIP_ONLY` / `FAILED` /
  `REVOKED`) as distinct text, sanitized scope (person, role, instant — no financial content),
  and the next action. Revoke via a `role="alertdialog"` confirm that passes the row version →
  concurrent change returns `CONFLICT` and the list reloads with a neutral notice. "Verified"
  success copy renders only after the service confirmed removal. `FAILED` rows offer a retry
  through `confirmResponsibility`.
- **`ALT_CLS_AxonCompanyResponsible.ResponsibilityView`** gains `revokedAt` + `lastError`
  (sanitized — only ever an `MSG_*` constant); `getResponsibilities` / `toView` /
  `listByBusiness` populate them.
- Reuses the AXF-83 versioned, exact-origin Account Team revocation contract unchanged — no
  independent access removed, no user deactivated, no Delete / ViewAll / ModifyAll introduced.

## Validation

- Jest **71/71** (full suite). New `aXF_LWC_companyResponsibleAccess` **8/8**;
  `aXF_LWC_contextBar` **5/5**.
- Apex `ALT_CLS_AxonCompanyResponsibleTest` + `AXF_CLS_CTRL_CompanyResponsibleTest` **35/35** on
  AXON_DEV, including new assertions for the admin view's `revokedAt` / sanitized `lastError`.
- ESLint + Prettier clean. Deployed to `AXON_DEV` with `NoTestRun`.

## Security

- `AXF_CanConfigure` enforced server-side on every entry point; neutral forbidden state in the UI.
- No optimistic TTL or client state used as authorization; revalidation clears reachable data
  before the `with sharing` / `WITH USER_MODE` server path.
- Revocation removes only the grant derived from the removed link; independent rights and the
  user are untouched. Previously downloaded or externally delivered copies remain outside Axon
  control and are stated as such in the UI.
- Sanitized scope only (person / role / instant); no financial content is shown to or about a
  revoked user.

## Related work

https://axon-personal-finances.atlassian.net/browse/AXF-8 — predecessors AXF-83 / AXF-7 / AXF-3
(merged). Component placement on the Business Account record page is a documented admin step.
