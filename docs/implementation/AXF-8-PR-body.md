## Summary

Implements AXF-8 convergence for revoked access across the Axon-controlled context surface.

## Changes

- Clears selected context and derived client state before authorization revalidation.
- Revalidates on reconnect, window focus, visible-tab return, and explicit retry.
- Adds an `AUTHORIZATION_REVALIDATION` LMS reason for consumers to discard stale data before refetching.
- Reuses the AXF-83 versioned, exact-origin Account Team revocation contract without removing independent access.

## Validation

- Focused Jest: 5/5 tests passing.
- Salesforce check-only: `0Afaj00000iuY7KCAU` — 2/2 metadata components succeeded.

## Security

- No optimistic TTL or client state is used as authorization.
- Revalidation clears reachable data before calling the `with sharing`/`WITH USER_MODE` server path.
- No user deactivation, Delete permission, View All, or Modify All is introduced.
- Previously downloaded or externally delivered copies remain outside Axon control.

## Related work

https://axon-personal-finances.atlassian.net/browse/AXF-8
