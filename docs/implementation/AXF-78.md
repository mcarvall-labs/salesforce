# AXF-78 — DEV cleanup inventory (AC1) and controlled removal plan

Status: **executed on AXON_DEV on 2026-09-15** (deploy `0Afaj00000kR09VCAS`, 25/25 components
removed) after Michel's written authorization of the manifest in chat ("Autorizado, pode remover as 4
classes e os Sites samples", AC4). Execution record in section 6. AXON_PROD is out of scope; UAT/PROD
follow the AXF-79 release plan.

Evidence baseline: read-only `sf org list metadata` / `SELECT COUNT()` against `AXON_DEV`
on 2026-09-15, compared with `origin/develop` (`87e667d`) and every open `feature/AXF-*`
branch.

## 1. Legacy candidates named by the story

| Component                                        | Present in AXON_DEV | Present in Git (any branch) | Disposition                                                                                      |
| ------------------------------------------------ | ------------------- | --------------------------- | ------------------------------------------------------------------------------------------------ |
| `AXF_OBJ_CashFlow__c` (D-50)                     | no                  | no                          | Nothing to migrate: `AXF_OBJ_FinancialTransaction__c` is the only ledger object in DEV (0 rows). |
| `Household__c` / `HouseholdKey` (D-51/D-77/D-78) | no                  | no                          | Absent; holder root is `Account` (Person/Business).                                              |
| `FinancialEntity__c` / `EntityKey`               | no                  | no                          | Absent.                                                                                          |
| `CommandExecution`, `AuditEvent`                 | no                  | no                          | Absent.                                                                                          |
| `BootstrapAuthority`                             | no                  | no                          | Absent.                                                                                          |
| EAG / HFE / invalidation / projector components  | no                  | no                          | Absent; must **not** be recreated.                                                               |
| Legacy bank text fields (AXF-106 supplement)     | see §2              | yes                         | Retain until AXF-106 replacements/mappings are verified.                                         |

The greenfield premise recorded in the G9 closure holds: none of the AXF-76-era objects exist
in AXON_DEV, so there is no data migration or expand–migrate–contract tranche to run for them.

## 2. Actual drift between AXON_DEV and Git

### 2.1 Metadata present in AXON_DEV but in no branch (removal candidates)

| Type          | API name                                                                                                                                                              | Origin                                                                        | Disposition                                                                                                                                                                                                                                                                             |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ApexClass     | `AXF_CLS_PluggyWebhookQueueable`                                                                                                                                      | AXF-11 intermediate design (removed in `6c48b12`)                             | **remove** (manifest §4)                                                                                                                                                                                                                                                                |
| ApexClass     | `AXF_CLS_PluggyWebhookSignature`                                                                                                                                      | AXF-11 intermediate design (removed in `7bb49e8`)                             | **remove** (manifest §4)                                                                                                                                                                                                                                                                |
| ApexClass     | `AXF_CLS_PluggyWebhookSignatureTest`                                                                                                                                  | same                                                                          | **remove** (manifest §4)                                                                                                                                                                                                                                                                |
| ApexClass     | `AXF_CLS_ScheduleReplenishmentStateReader`                                                                                                                            | AXF-103 intermediate design (never committed)                                 | **remove** (manifest §4)                                                                                                                                                                                                                                                                |
| ApexClass ×10 | `SiteLoginController(+Test)`, `SiteRegisterController(+Test)`, `ChangePasswordController(+Test)`, `ForgotPasswordController(+Test)`, `MyProfilePageController(+Test)` | Salesforce Sites samples generated when the `Pluggy_Webhook` site was enabled | **removed** with the 10 sample pages of the login/registration flow and the `SiteLogin` component (manifest §4). The 7 pages the CustomSite references, `SiteHeader`/`SiteFooter`/`SitePoweredBy` and the `SiteSamples` static resource stay: they are the site's error/template pages. |
| PermissionSet | `Experience_Profile_Manager`                                                                                                                                          | Standard, created by Experience Cloud                                         | retain (platform-owned)                                                                                                                                                                                                                                                                 |
| FlexiPage ×14 | `*_UtilityBar`                                                                                                                                                        | Standard app utility bars                                                     | retain (platform-owned)                                                                                                                                                                                                                                                                 |
| LWC ×7        | `devedapp__*`                                                                                                                                                         | Developer Edition sample package (`devedapp` namespace)                       | retain; not deletable via destructive changes                                                                                                                                                                                                                                           |

No custom object, trigger, custom permission, tab, app, permission set group, or custom
metadata record in AXON_DEV is missing from Git.

### 2.2 Metadata in AXON_DEV that only exists on open Sprint 3 branches (retain)

These are pending merges, not obsolete components. Removing them would break the PRs' tests:
`AXF_OBJ_BillingDocument*__c` (AXF-65), `AXF_OBJ_ClosureRun__c` (AXF-119),
`AXF_OBJ_EconomicAllocation(Set)__c` (AXF-126), `AXF_OBJ_FinancialSchedule__c` /
`AXF_OBJ_Schedule*__c` / `AXF_ScheduleReplenishmentPolicy__mdt` (AXF-103),
`AXF_OBJ_SharedExpenseGrant__c` (AXF-6), `AXF_OBJ_TransactionObservation__c` (AXF-109),
`AXF_CMT_ConfidencePolicy__mdt` (AXF-143), `AXF_CMT_CsvFormat__mdt` (AXF-72), 62 Apex classes,
13 triggers, 5 LWCs, 7 custom permissions, 4 tabs.

### 2.3 Git metadata missing from AXON_DEV

`objects/AccountContactRelation` (field metadata only) — not deployed yet; not a cleanup item.

## 3. Data baseline (AC2 reconciliation anchor)

Record counts in AXON_DEV on 2026-09-15 (all other `AXF_OBJ_*` objects: 0 rows):

| Object                           | Rows |
| -------------------------------- | ---- |
| `AXF_OBJ_AccessProvisioning__c`  | 1    |
| `AXF_OBJ_AccountHolder__c`       | 1    |
| `AXF_OBJ_BankAccount__c`         | 3    |
| `AXF_OBJ_BankInstitution__c`     | 3    |
| `AXF_OBJ_CreditCard__c`          | 5    |
| `AXF_OBJ_IntegrationRun__c`      | 3    |
| `AXF_OBJ_OnboardingProgress__c`  | 1    |
| `AXF_OBJ_OnboardingStep__c`      | 8    |
| `AXF_OBJ_PluggyConnection__c`    | 3    |
| `AXF_PluggyIntegrationConfig__c` | 1    |
| `AXF_ReportCurrencyPref__c`      | 1    |

No financial fact rows exist (`BankAccountTransaction`, `CreditCardTransaction`,
`FinancialTransaction` = 0), so the "sum by original currency" reconciliation is trivially
0 for every currency. The counts above are the before/after parity check for the manifest in §4,
which touches no data.

## 4. Destructive manifest (authorized 2026-09-15, executed)

`scripts/cleanup/axf-78/destructiveChanges.xml`
(sha256 `69a75b546638571bb90a6429e93152fc51a86c2ec6b2b269fe9b11ad3e711a3f`) removes 25 components:

| Type          | Members                                                                                                                                                                                                                                                                                      |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ApexClass ×14 | `AXF_CLS_PluggyWebhookQueueable`, `AXF_CLS_PluggyWebhookSignature(+Test)`, `AXF_CLS_ScheduleReplenishmentStateReader`, `ChangePasswordController(+Test)`, `ForgotPasswordController(+Test)`, `MyProfilePageController(+Test)`, `SiteLoginController(+Test)`, `SiteRegisterController(+Test)` |
| ApexPage ×10  | `AnswersHome`, `ChangePassword`, `ForgotPassword`, `ForgotPasswordConfirm`, `IdeasHome`, `MyProfilePage`, `SiteLogin`, `SiteRegister`, `SiteRegisterConfirm`, `Unauthorized`                                                                                                                 |
| ApexComponent | `SiteLogin`                                                                                                                                                                                                                                                                                  |

Dependency analysis before execution (retrieved sources): `Unauthorized` embeds `c:SiteLogin`, whose
controller `SiteLoginController` links `$Page.ForgotPassword` / `$Page.SiteRegister`; the
`Pluggy_Webhook` CustomSite pointed `authorizationRequiredPage` at `Unauthorized`. Everything else
in the removal set is referenced only from inside the set. The pages kept (`BandwidthExceeded`,
`Exception`, `FileNotFound`, `InMaintenance`, `SiteTemplate`, `StdExceptionTemplate`,
`UnderConstruction`) are the ones the site still references; they reference only
`SiteHeader`/`SiteFooter`/`SitePoweredBy` and `$Resource.SiteSamples`, which are also kept.

Steps, in order:

1. **Backup (AC2)** — `scripts/cleanup/axf-78/backup.sh` retrieved the 25 components into
   `_bmad-output/backups/axf-78/20260915T162214Z/` (git-ignored), plus
   `site-before/Pluggy_Webhook.site` with the CustomSite as it was. Recovery:
   `sf project deploy start -o AXON_DEV --metadata-dir <backup>/unpackaged`, then redeploy
   `site-before` to restore `authorizationRequiredPage`.
2. **Site pre-step** — deployed the CustomSite with `authorizationRequiredPage` unset (deploy
   `0Afaj00000kQsrtCAC`; the field is optional, Salesforce serves its default page). The site stays
   active with `indexPage = UnderConstruction`, as documented in AXF-11 §10.
3. **Validation (AC3)** — `scripts/cleanup/axf-78/validate.sh` (check-only, `RunLocalTests`):
   `0Afaj00000kQtWDCA0`, 0 component failures, 818/820 tests passed. The 2 failures reproduce
   standalone before any deletion and are org-state issues unrelated to the manifest (section 5).
4. **Execution (AC4)** — `sf project deploy start --manifest package.xml --post-destructive-changes
destructiveChanges.xml --test-level NoTestRun`: `0Afaj00000kR09VCAS`, 25/25 deleted.
5. **Evidence (AC5/AC6)** — section 6.

## 5. Out of scope / follow-ups

- Two `RunLocalTests` failures on AXON_DEV, present before and independent of this cleanup, logged
  in `_bmad-output/implementation-artifacts/deferred-work.md`:
  `AXF_CLS_AccessConfigEffectiveTest.systemAdministratorIsNotAConfiguradorByDefault` (the admin
  user running the tests holds `AXF_CanConfigure` through the `AXF_PSG_GestorFinanceiro`
  assignment made so the Axon UI is visible) and
  `AXF_CLS_HolderAccessTest.gestorCanRegisterAndEditButNotDelete` (`saveHolder` returns FAILED for
  the built Gestor user).
- Owner-sync backfill, `AXF_BA/CC_LKP_Account__c` → required/Restrict and
  `AXF_CCI_EXT_ExternalId__c` collision are G9 execution items tracked separately; they are not
  removals and are not in this manifest.

## 6. Execution record (2026-09-15)

| Check                                          | Before (§2.1 / §3)                                 | After                                                                                |
| ---------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------ |
| ApexClass in AXON_DEV and in no branch         | 4 AXF orphans + 10 Sites samples + 4 `devedapp__*` | only the 4 `devedapp__*` (managed sample package, retained)                          |
| ApexPage in AXON_DEV                           | 17                                                 | 7 (all referenced by the `Pluggy_Webhook` site)                                      |
| ApexComponent in AXON_DEV                      | 4                                                  | 3 (`SiteFooter`, `SiteHeader`, `SitePoweredBy`)                                      |
| `Pluggy_Webhook` site                          | Active                                             | Active; `GET /` → 200, `POST /services/apexrest/pluggy/webhook` without secret → 401 |
| Record counts (11 objects of §3 + BAT/CCT/FTX) | 1,1,3,3,5,3,1,8,3,1,1 / 0,0,0                      | identical                                                                            |

Deploy ids: site pre-step `0Afaj00000kQsrtCAC`, validation `0Afaj00000kQtWDCA0`, execution
`0Afaj00000kR09VCAS`. Manifest sha256
`69a75b546638571bb90a6429e93152fc51a86c2ec6b2b269fe9b11ad3e711a3f`.
