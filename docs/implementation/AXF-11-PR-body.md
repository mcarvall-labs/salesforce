<!-- PR body for: AXF-11: reconciled/base  (head: feature/AXF-11-pluggy-credentials-consent) -->

## Related work

- Jira: https://axon-personal-finances.atlassian.net/browse/AXF-11 — _Configurar credenciais e controlar o consentimento Pluggy_ (Epic AXF-10)
- Local record: `docs/implementation/AXF-11.md`
- Base: `reconciled/base` (greenfield line — carries the AXF-7 / AXF-80 / AXF-89 predecessors; not yet on `develop`)

## Contract

Gates **G1/G2/G4/G6/G7 — definition phase closed (30/08/2026)**. Implementation follows
`ARCHITECTURE-SPINE.md` §"Fechamento G4", the `AXF-11-G4-investigacao` note, and the
28/08 decision _local pause, no `DELETE /items`_.

## What this delivers

| Area                                | Component                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Connection identity & consent state | `AXF_OBJ_PluggyConnection__c` — `AXF_CON_EXI_PluggyItemId__c` (operation key) + `AXF_CON_TXT_ObservedItemId__c` (never a key), `AXF_CON_PKL_ConsentState__c` `ACTIVE\|STALE\|REVOKED`, `AXF_CON_PKL_CollectionState__c`, consent evidence fields (institution, scope, purpose, given/expires, version)                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Secure credentials + rotation       | `AXF_EXC_Pluggy` / `AXF_EXC_Pluggy_Candidate` + `AXF_NC_Pluggy_API` / `_Candidate`; `AXF_CLS_PluggyCredentialRotationService` tests the candidate (auth + `GET /connectors` + existing connections reachable) then **promotes by flipping an active-slot pointer** — the live credential is never destroyed. Secrets are entered only through the native Setup UI.                                                                                                                                                                                                                                                                                                                                                                             |
| apiKey handling (regressed legacy)  | `AXF_CLS_PluggyAuthService` ported from `develop` and cleaned per AC8: every request/response/apiKey `System.debug` removed, apiKey held **only in memory** for the transaction (one `POST /auth` per transaction; no Platform Cache — 31/08 revision), sanitized errors (endpoint + status + correlation id only)                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Consent capture / revalidation      | `AXF_CLS_PluggyConsentService` — `GET /items` + `GET /consents`; `null` `expiresAt` stays `null` (not "eternal", not an error); `403` on `/consents` is **not** proof of revocation; the two Item IDs are preserved separately (D-85)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| Collection gate + pause             | `AXF_CLS_PluggyCollectionControlService.assertCollectionAllowed` (for AXF-12 jobs) + local/global pause; resume requires a **successful consent revalidation**; pause never revokes consent or deletes history; no `DELETE /items`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Webhook                             | `AXF_CLS_PluggyWebhookResource` (Site guest user) — **shared-secret header** check (`AXF_CLS_PluggyWebhookAuth`, constant-time) **before** anything is accepted; Pluggy does **not** sign its webhooks, so the secret is registered as a custom header on the Pluggy webhook and matched against a protected Custom Metadata type (`AXF_PluggyWebhookConfig__mdt`). A valid payload only **publishes `AXF_PluggyWebhookEvent__e`** (guest can only `Create`), never stored as a fact. `AXF_TRG_PluggyWebhookEvent` → `AXF_CLS_PluggyWebhookEventHandler` runs the consent revalidation **out of the guest context** (Automated Process user) via the bulk `AXF_CLS_PluggyConsentService.refreshByItemIds` (all callouts before the single DML) |
| UI                                  | `aXF_LWC_pluggyIntegrationConfig` (status / rotation / global pause) and `aXF_LWC_sourceHealth` ("Saúde das fontes": institution, consent, last success, impact, permitted action), text-based status (no colour/toast-only), error associated to the row                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Access                              | `AXF_PS_PluggyIntegration` (service principal, min access) + `AXF_PS_GestorFinanceiro` wiring; `AXF_CanConfigure` enforced server-side for every mutation                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |

## Out of scope (own slices)

Discovery (AXF-84), sync / `IntegrationRun` / cursors (AXF-12), external-ID uniqueness
(AXF-13), illustrated guide (AXF-89), `DELETE /items` (deferred). Publicly exposing the
webhook endpoint (Site + guest user), assigning `AXF_PS_PluggyIntegration` to the Automated
Process user, and populating the real secrets are documented manual install steps
(see `docs/implementation/AXF-11.md` §10 / AXF-77).

## Validation

- Baseline AXF-11: **67 Apex tests + Jest suite — all green** before the final webhook correction.
- Final webhook regression: **12/12 Apex tests passed** (`707aj00001CJbPW`), with 88% on
  `AXF_CLS_PluggyWebhookResource` and 93% on `AXF_CLS_PluggyWebhookEventHandler`.
- Manual Site test returned `accepted=true`, `queued=true`; the CMT layout includes the
  editable webhook-secret field without versioning its value.
- Correction deployed to `AXON_DEV` with `NoTestRun` (`0Afaj00000ipUfSCAU`).
- ESLint + Prettier clean.

## Reviewer notes / deliberate choices

1. **Rotation = slot-pointer flip, not `ConnectApi` credential writes.** Avoids granting
   `Manage Named Credentials` broadly and matches the G4 investigation's "two pre-installed
   NC/EC sets" design. Admins enter both secrets in Setup.
2. **Gestor PS gets the External Credential principal access** (active + candidate, not
   webhook) so the authorized configurator can run connectivity tests synchronously.
   `AXF_PS_PluggyIntegration` remains the service-user principal.
3. **Webhook auth = shared-secret header, not HMAC.** Pluggy does not sign its webhooks; it
   only forwards custom headers registered on the webhook (via `POST /webhooks` `headers`).
   So we register `X-Webhook-Token: <secret>` and compare it constant-time
   (`AXF_CLS_PluggyWebhookAuth`) against a protected Custom Metadata type
   (`AXF_PluggyWebhookConfig__mdt` — EC values can't be read in Apex; G4-3 allows a protected
   CMT). Defence in depth: the handler only runs an idempotent revalidation via the
   authenticated API, so a forged POST injects no data.
4. **Webhook → platform event bridge.** The Salesforce Site guest-user license forbids
   `Edit` on a custom object and use of an External Credential, so the guest user cannot run
   the consent-revalidation callout+DML itself. It verifies the secret and publishes
   `AXF_PluggyWebhookEvent__e` (only `Create` needed); `AXF_TRG_PluggyWebhookEvent` runs the
   revalidation as the Automated Process user, which must carry `AXF_PS_PluggyIntegration`
   (manual step). `publishBehavior = PublishImmediately` so a verified notification is not
   lost if the rest of the request fails; the revalidation is idempotent.
5. **PR targets `reconciled/base`**, where the AXF-7/80/89 predecessors live. Retarget to
   `develop` if the greenfield line is promoted first.
