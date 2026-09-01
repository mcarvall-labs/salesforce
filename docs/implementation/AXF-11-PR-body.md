<!-- PR body for: AXF-11: reconciled/base  (head: feature/AXF-11-pluggy-credentials-consent) -->

## Related work

- Jira: https://axon-personal-finances.atlassian.net/browse/AXF-11 — *Configurar credenciais e controlar o consentimento Pluggy* (Epic AXF-10)
- Local record: `docs/implementation/AXF-11.md`
- Base: `reconciled/base` (greenfield line — carries the AXF-7 / AXF-80 / AXF-89 predecessors; not yet on `develop`)

## Contract

Gates **G1/G2/G4/G6/G7 — definition phase closed (30/08/2026)**. Implementation follows
`ARCHITECTURE-SPINE.md` §"Fechamento G4", the `AXF-11-G4-investigacao` note, and the
28/08 decision *local pause, no `DELETE /items`*.

## What this delivers

| Area | Component |
|---|---|
| Connection identity & consent state | `AXF_OBJ_PluggyConnection__c` — `AXF_CON_EXI_PluggyItemId__c` (operation key) + `AXF_CON_TXT_ObservedItemId__c` (never a key), `AXF_CON_PKL_ConsentState__c` `ACTIVE\|STALE\|REVOKED`, `AXF_CON_PKL_CollectionState__c`, consent evidence fields (institution, scope, purpose, given/expires, version) |
| Secure credentials + rotation | `AXF_EXC_Pluggy` / `AXF_EXC_Pluggy_Candidate` + `AXF_NC_Pluggy_API` / `_Candidate`; `AXF_CLS_PluggyCredentialRotationService` tests the candidate (auth + `GET /connectors` + existing connections reachable) then **promotes by flipping an active-slot pointer** — the live credential is never destroyed. Secrets are entered only through the native Setup UI. |
| apiKey handling (regressed legacy) | `AXF_CLS_PluggyAuthService` ported from `develop` and cleaned per AC8: every request/response/apiKey `System.debug` removed, short configurable Platform Cache TTL, sanitized errors (endpoint + status + correlation id only) |
| Consent capture / revalidation | `AXF_CLS_PluggyConsentService` — `GET /items` + `GET /consents`; `null` `expiresAt` stays `null` (not "eternal", not an error); `403` on `/consents` is **not** proof of revocation; the two Item IDs are preserved separately (D-85) |
| Collection gate + pause | `AXF_CLS_PluggyCollectionControlService.assertCollectionAllowed` (for AXF-12 jobs) + local/global pause; resume requires a **successful consent revalidation**; pause never revokes consent or deletes history; no `DELETE /items` |
| Webhook | `AXF_CLS_PluggyWebhookResource` — HMAC-SHA256 **constant-time** signature check **before** anything is accepted; a valid payload only **triggers a fetch**, never stored as a fact; secret in a protected Custom Metadata type (`AXF_PluggyWebhookConfig__mdt`) |
| UI | `aXF_LWC_pluggyIntegrationConfig` (status / rotation / global pause) and `aXF_LWC_sourceHealth` ("Saúde das fontes": institution, consent, last success, impact, permitted action), text-based status (no colour/toast-only), error associated to the row |
| Access | `AXF_PS_PluggyIntegration` (service principal, min access) + `AXF_PS_GestorFinanceiro` wiring; `AXF_CanConfigure` enforced server-side for every mutation |

## Out of scope (own slices)

Discovery (AXF-84), sync / `IntegrationRun` / cursors (AXF-12), external-ID uniqueness
(AXF-13), illustrated guide (AXF-89), `DELETE /items` (deferred). Publicly exposing the
webhook endpoint (Site + guest user) and populating the real secrets are documented
manual install steps (AXF-77).

## Validation

- **56 Apex tests + 11 Jest tests — all green.** Per-class Apex coverage 81–100% on the
  new classes (exception classes carry no executable lines).
- Deployed to `AXON_DEV` with `NoTestRun` (project delivery rule); tests run separately.
- ESLint + Prettier clean.

## Reviewer notes / deliberate choices

1. **Rotation = slot-pointer flip, not `ConnectApi` credential writes.** Avoids granting
   `Manage Named Credentials` broadly and matches the G4 investigation's "two pre-installed
   NC/EC sets" design. Admins enter both secrets in Setup.
2. **Gestor PS gets the External Credential principal access** (active + candidate, not
   webhook) so the authorized configurator can run connectivity tests synchronously.
   `AXF_PS_PluggyIntegration` remains the service-user principal.
3. **Webhook secret in a protected Custom Metadata type** — External Credential values
   cannot be read in Apex for local HMAC; G4-3 explicitly allows "credencial própria **ou
   Custom Metadata protegida**".
4. **PR targets `reconciled/base`**, where the AXF-7/80/89 predecessors live. Retarget to
   `develop` if the greenfield line is promoted first.
