# AXF-8 — Revoke derived access and revalidate reachable surfaces

- Jira: https://axon-personal-finances.atlassian.net/browse/AXF-8
- Branch: `feature/AXF-8-revoke-derived-access`
- Base: `reconciled/base`

## Implementation

The Account Team grant owned by an Axon company-responsibility record continues to be revoked by `ALT_CLS_AxonCompanyResponsible`. That implementation validates the persisted version, removes only the exact managed `AccountTeamMember`, preserves independent grants, verifies the managed relationship removal, and only then reports `REVOKED`. Partial or unverifiable removal remains fail-closed as `FAILED` or preserves the effective `GRANTED` state.

AXF-8 adds client-side convergence to `aXF_LWC_contextBar`:

- clear the selected context and all server-returned options before revalidation;
- publish `AUTHORIZATION_REVALIDATION` through `AXF_ContextChanged__c` so consumers clear derived state before refetching;
- revalidate through the secure `WITH USER_MODE` context query on window focus, reconnect, visible-tab return, and explicit retry;
- announce the neutral revalidation state through the existing accessible live region;
- never restore a prior context from client storage or replay queued mutations.

## Controlled-surface boundary

The current authorized context is the Axon-controlled cache/navigation surface introduced by AXF-3. Server operations remain responsible for `with sharing`, CRUD/FLS, and current-record authorization on every call. Files or messages already delivered outside Salesforce/Axon control cannot be remotely erased.

## Validation

- Focused Jest suite covers normal selection, neutral empty/error states, and reconnect invalidation.
- Existing `ALT_CLS_AxonCompanyResponsibleTest` covers exact managed-team revocation, independent member preservation, stale versions, missing managed effects, cross-company denial, and reactivation.
- Salesforce check-only `0Afaj00000iuY7KCAU`: 2/2 metadata components succeeded with no component errors.
