# AXF-8 — Revoke derived access and revalidate reachable surfaces

- Jira: https://axon-personal-finances.atlassian.net/browse/AXF-8
- Branch: `feature/AXF-8-revoke-derived-access`
- Base: `reconciled/base`
- Predecessors: AXF-83, AXF-7, AXF-3 (all merged into `reconciled/base`).

## Scope split

The **server un-grant** ships with **AXF-83** (`ALT_CLS_AxonCompanyResponsible`): it validates the
persisted version, removes only the exact managed `AccountTeamMember` + its row cause, preserves
every independent grant (PS/PSG, ownership, other teams), never deactivates the user, verifies the
managed-relationship removal, and only then reports `REVOKED`. Partial or unverifiable removal stays
fail-closed as `FAILED` (retryable) or preserves the effective `GRANTED` state.

AXF-8 adds, on top of that:

1. **Client-side convergence** on the Axon-controlled context surface.
2. **The administrative view** of the effective revocation/grant state (AC5).

## 1. Client convergence — `aXF_LWC_contextBar`

- Clears the selected context and every server-returned option before revalidation.
- Publishes `AUTHORIZATION_REVALIDATION` through `AXF_ContextChanged__c` (new `changeReason` field)
  so any consumer discards derived state before refetching.
- Revalidates through the secure `WITH USER_MODE` context query on window focus, `online`,
  visible-tab return, and explicit retry.
- Announces the neutral revalidation state through the existing `aria-live` region.
- Never restores a prior context from client storage and never replays queued mutations.

## 2. Administrative view — `aXF_LWC_companyResponsibleAccess` (AC5)

Placed on a **Business Account** record page (also available as an App/Tab component). Reads
`AXF_CLS_CTRL_CompanyResponsible.getResponsibilities(businessId)` and renders one row per
responsible with the **effective** state — never the requested state:

| CRA status          | Shown as                                                            | Next action                                    |
| ------------------- | ------------------------------------------------------------------- | ---------------------------------------------- |
| `GRANTED`           | "Acesso concedido" + granted-on                                     | **Retirar acesso** (confirm dialog)            |
| `RELATIONSHIP_ONLY` | "Aguardando usuário vinculado"                                      | informational — granted when a user is linked  |
| `FAILED`            | "Falha ao conceder" + sanitized reason (`AXF_CRA_TXT_LastError__c`) | **Tentar novamente** (`confirmResponsibility`) |
| `REVOKED`           | "Acesso retirado" + revoked-on                                      | none                                           |

- Scope shown is sanitized: person name (redacted to `—` when the caller cannot see it), business
  role (sócia/administradora), and the instant — **never financial content**.
- Revoke goes through a `role="alertdialog"` confirm (Escape cancels, focus moves in and back out);
  it passes the row `version` so a concurrent change returns `CONFLICT` → the list reloads with a
  neutral "mudou em outra sessão" notice (AC "revogação concorrente").
- "Só confirma remoção após verificação": the success message ("Acesso retirado e verificado.")
  only renders when the service returned `REVOKED` after its own team-member + relationship checks.
- `AXF_CanConfigure` is enforced server-side on every entry point; the LWC shows a neutral
  forbidden state when `canConfigure()` is false.
- `ResponsibilityView` gained `revokedAt` + `lastError` (sanitized — only ever an `MSG_*` constant);
  `getResponsibilities` / `toView` / the `listByBusiness` SOQL populate them.

## Controlled-surface boundary

The Axon-controlled reachable surface is the authorized-context cache/navigation introduced by
AXF-3 plus this admin view. Server operations remain responsible for `with sharing`, CRUD/FLS and
current-record authorization on every call. Files or messages already delivered outside
Salesforce/Axon control cannot be remotely erased — this is stated in the UI copy, not promised
away. Any future reachable surface, cache or job must honour the `AUTHORIZATION_REVALIDATION`
reason before disclosure (AC6); there is no optimistic TTL and no reauthorizing retry.

## Validation

- **Jest**: full suite **71/71**. `aXF_LWC_contextBar` 5/5 (normal selection, neutral empty/error,
  reconnect invalidation). `aXF_LWC_companyResponsibleAccess` 8/8 (forbidden, no-business, four
  distinct textual statuses + sanitized failure reason + revoked instant, revoke-only-on-granted /
  retry-only-on-failed, confirm-then-verified-result, concurrent-change → reload notice, retry via
  `confirmResponsibility`, sanitized wire error).
- **Apex**: `ALT_CLS_AxonCompanyResponsibleTest` + `AXF_CLS_CTRL_CompanyResponsibleTest` **35/35**
  on AXON_DEV — exact managed-team revocation, independent-member preservation, stale versions,
  missing managed effect, cross-company denial, reactivation, and the new assertions that the admin
  view surfaces `revokedAt` and the sanitized `lastError`.
- ESLint + Prettier clean.
- Deploy to `AXON_DEV` with `NoTestRun` (project rule); tests run separately.

## Page placement

`AXF_Account_Record_Page.flexipage` (new, in this PR) is an Account record page carrying
`c:aXF_LWC_companyResponsibleAccess` with a visibility rule `RecordType.DeveloperName = AXF_Business`
(plus the standard highlights + detail panels). It is the first FlexiPage in the greenfield line.

**One manual step:** activate it in Setup → Object Manager → Account → Lightning Record Pages →
_Axon - Account Record Page_ → **Activation** → _Assign as Org Default_ (Desktop). FlexiPage
activation is not deployable metadata; the page itself is.
