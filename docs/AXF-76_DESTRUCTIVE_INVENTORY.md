# AXF-76 destructive-change inventory

Status: zero-dependency evidence verified; destructive deployment authorized, executed, and validated exclusively in AXON_DEV.

## Validated functional cutover

- AXON_DEV functional dry-run `0Affj00000ObfuSCAR` compiled 29/29 components and passed 23/23 tests.
- AXON_DEV integrated functional plus post-destructive check-only `0Affj00000ObZPHCA3` succeeded with 36 components, 23/23 tests, and `checkOnly=true`.
- AXON_DEV functional deployment `0Affj00000OcVeUCAV` succeeded with 29 components and 23/23 tests.
- Authorized AXON_DEV integrated destructive deployment `0Affj00000OgGNWCA3` succeeded with 36 components and 23/23 tests.
- Post-destructive test run `707fj00000wAPSa` passed 24/24 tests. The four legacy objects and the legacy revocation class are absent; CommandExecution, AuditEvent, and BootstrapAuthority remain present.
- Post-review check-only `0Affj00000OfrfGCAR` succeeded with 29 components and 29 tests. Final functional deployment `0Affj00000OgOcoCAF` succeeded with 29/29 components using `NoTestRun`; separate targeted test run `707fj00000wB7qN` passed 30/30 tests.
- The versioned functional manifest is `manifest/AXF-76/functionalPackage.xml`; only the reviewed delta and required dependencies are included.
- Explicit EN owner/PT-BR target fixtures were deployed as `0Affj00000Og2oXCAR`; targeted run `707fj00000wApeu` passed 30/30 tests without localized profile-name matching.
- Bootstrap, Financial Entity authorization, selectors, gateways, controller, LWC, service-principal rotation, and their tests no longer consume EAG, HFE, AIN, or SPR.
- Record scope is derived from private ownership/Axon shares plus CRUD/FLS and Custom Permissions.
- `AXF_OBJ_CommandExecution__c`, `AXF_OBJ_AuditEvent__c`, `AXF_OBJ_BootstrapAuthority__c`, the service-principal resolver/provisioner, and the technical Permission Set remain retained.

## Local reference inventory

### Migrated production consumers

| Consumer                                   | Status                                                                                  |
| ------------------------------------------ | --------------------------------------------------------------------------------------- |
| `ALT_CLS_HouseholdBootstrapGateway`        | Migrated; no EAG/HFE/SPR creation and no grant-version audit value.                     |
| `ALT_CLS_FinancialEntityAuthorization`     | Migrated to native visible-record checks and capability ceiling.                        |
| `ALT_CLS_FinancialEntitySelector`          | Migrated to `with sharing` and USER_MODE without EAG prefilter.                         |
| `ALT_CLS_FinancialEntityGateway`           | Migrated to functional-user ownership without HFE/EAG creation.                         |
| `AXF_CLS_CTRL_FinancialEntity` and its LWC | Migrated to assign/remove Axon shares.                                                  |
| `ALT_CLS_ServicePrincipalProvisioner`      | Retained only for technical roots; no EAG/AIN/SPR or Household/FIE ownership inventory. |
| `AXF_PS_SecurityProjector`                 | Retained for technical principals; legacy object CRUD references removed.               |

### Removed local source and retained destructive targets

The following legacy artifacts have been removed from `force-app` and remain intentionally listed in `destructiveChangesPost.xml` so the reviewed org-side deletion is reproducible:

- Apex class `ALT_CLS_AuthorizationRevocationService` and its metadata file.
- Custom objects `AXF_OBJ_EntityAccessGrant__c`, `AXF_OBJ_HouseholdFinancialEntity__c`, `AXF_OBJ_AuthorizationInvalidation__c`, and `AXF_OBJ_SharingProjectorRun__c`, including their child fields and validation rules.
- Custom Permission `AXF_RevokeEntityAccess`.
- Audit field `AXF_OBJ_AuditEvent__c.AXF_AUE_NUM_GrantVersion__c`.

No deployable local source remains for these targets. AIN had a required lookup to EAG, so both objects remain grouped in the same post-destructive phase.

### Tests and documentation

- Active Apex and Jest tests contain no EAG/HFE/AIN/SPR fixtures or behavioral dependencies.
- This inventory is the only retained documentation of the obsolete component names in the implementation delta.
- Historical planning/specification records outside the Salesforce repository are evidence and must not be rewritten or treated as deployable dependencies.

## Zero-dependency status and blockers

Local migrated-consumer status: **zero production dependencies**. The only intentional local references are the reviewed destructive manifest and this inventory evidence.

AXON_DEV zero-dependency evidence is **verified**:

1. Record counts were zero for `AXF_OBJ_EntityAccessGrant__c`, `AXF_OBJ_HouseholdFinancialEntity__c`, `AXF_OBJ_AuthorizationInvalidation__c`, and `AXF_OBJ_SharingProjectorRun__c`.
2. The full `MetadataComponentDependency` result contained no references to any destructive target.
3. Functional dry-run `0Affj00000ObfuSCAR` passed 29/29 components and 23/23 tests.
4. Integrated functional plus post-destructive check-only `0Affj00000ObZPHCA3` passed 36 components and 23/23 tests with `checkOnly=true`.

No destructive blocker remains for AXON_DEV. The reviewed package was explicitly authorized by the human and executed successfully as deployment `0Affj00000OgGNWCA3`.

AXON_PROD remains prohibited. Do not execute either destructive manifest without the evidence and approval above.
