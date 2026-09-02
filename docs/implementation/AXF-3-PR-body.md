## Summary

Implements AXF-3 with an authorized Account context bar backed exclusively by Salesforce sharing and CRUD/FLS.

## Changes

- Adds a `with sharing`/`WITH USER_MODE` context service and a sanitized LWC controller.
- Adds an accessible context picker and Lightning Message Service contract with monotonically increasing selection versions.
- Grants controller/tab access to Gestor Financeiro and Participante without Delete, ViewAll, or ModifyAll.
- Adds focused Apex and Jest tests.

## Validation

- Salesforce check-only: `0Afaj00000itM9pCAE` — 9/9 components and 5/5 Apex tests; service 88% and controller 80% coverage.
- Jest: 4/4 focused tests.
- Static analysis: PMD/CPD/regex found no high or moderate code violations; the optional Flow engine was unavailable because Python was not configured.

## Deployment notes

No persistent UAT/PROD deployment was performed.

## Risks

Consumers of `AXF_ContextChanged__c` must clear their previous view and refetch data for the new `selectionVersion`; the message itself never grants access.

## Related work

https://axon-personal-finances.atlassian.net/browse/AXF-3
