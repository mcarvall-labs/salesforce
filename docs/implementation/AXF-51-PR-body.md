<!-- PR body for: AXF-51: reconciled/base (head: feature/AXF-51-counterparty-management) -->

## Summary

Implements counterparty and contextual relationship management per holder entity (`AXF-51`), establishing the core architecture for external business partners, clients, and service providers (G1, G2, AD-30, GF-32).

## Domain Principles & Invariants

- **Minimal Canonical Identity (G1, AD-30):** Root `AXF_OBJ_Counterparty__c` contains only legal name, display name, kind (`PERSON` | `ORGANIZATION`), country ISO-2, status, external ID, and version. No contact or address PII resides on the root.
- **Cross-Entity Isolation (G2, GF-32):** Contextual attributes reside strictly on `AXF_OBJ_CounterpartyEntityRelationship__c`, linking the counterparty to a specific holder entity (`Account`). Users authorized on Entity A only see minimal counterparty identity + Entity A's relationship. Other relationships are never exposed or inferred.
- **Protected Tax Identifier (AD-30, GF-24):** Persisted in `AXF_OBJ_CounterpartyTaxIdentifier__c` strictly as formatted mask (e.g. `•••.•••.789-01`, `••.•••.•••/0001-90`) and HMAC-SHA-256 framed search digest (`AXF_CLS_IdentityFraming`). Raw reversible tax numbers are strictly prohibited.
- **Apex Managed Sharing (G2-3):** Derived via `RowCause AXF_CounterpartyRelationAccess__c` for both Counterparty (Read) and Relationship (Edit) granted to the entity owner.

## Changes

- **Schema:**
  - `AXF_OBJ_Counterparty__c` + Custom Sharing Reason `AXF_CounterpartyRelationAccess__c`
  - `AXF_OBJ_CounterpartyEntityRelationship__c` + Custom Sharing Reason `AXF_CounterpartyRelationAccess__c`
  - `AXF_OBJ_CounterpartyTaxIdentifier__c`
  - Custom Tab `AXF_Counterparties`
- **Apex Domain & Controller:**
  - `ALT_CLS_CounterpartyService`: framing keys, safe masking, HMAC digest calculation, optimistic concurrency, cross-entity query isolation, and Apex managed sharing grants.
  - `AXF_CLS_CTRL_CounterpartyManagement`: thin `@AuraEnabled` controller with sanitized exceptions.
  - `AXF_CLS_CounterpartyException`: domain-specific exception class.
- **UI:**
  - `aXF_LWC_counterpartyManagement`: master-detail view with entity selector, reactive search, counterparty list, detail panel with protected tax ID, and modal form for create/edit.
- **Security:**
  - Updated `AXF_PS_GestorFinanceiro` (CRUD access + tab visible)
  - Updated `AXF_PS_Participante` (Read-only access + tab visible)
- **Tests:**
  - `ALT_CLS_CounterpartyServiceTest`: 100% passing (90% coverage).
  - `AXF_CLS_CTRL_CounterpartyManagementTest`: 100% passing (89% coverage).
  - `aXF_LWC_counterpartyManagement` Jest unit tests.

## Validation

- Verified on `AXON_DEV`: 12/12 Apex tests passed.
- Deployment validated and deployed to `AXON_DEV`.

## Related Work

- Parent: https://axon-personal-finances.atlassian.net/browse/AXF-50
- Issue: https://axon-personal-finances.atlassian.net/browse/AXF-51
- Predecessors: AXF-80, AXF-7 (merged).
