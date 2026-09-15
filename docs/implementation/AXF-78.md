# AXF-78 — DEV cleanup inventory (AC1) and controlled removal plan

Status: **inventory and plan only**. No org operation, backup, or deletion was executed. Every
destructive step below waits for Michel's explicit authorization of the exact manifest
(AC4). AXON_PROD is out of scope; UAT/PROD follow the AXF-79 release plan.

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

| Type          | API name                                                                                                                                                              | Origin                                                                        | Disposition                                                                                                                                                              |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| ApexClass     | `AXF_CLS_PluggyWebhookQueueable`                                                                                                                                      | AXF-11 intermediate design (removed in `6c48b12`)                             | **remove** (manifest §4)                                                                                                                                                 |
| ApexClass     | `AXF_CLS_PluggyWebhookSignature`                                                                                                                                      | AXF-11 intermediate design (removed in `7bb49e8`)                             | **remove** (manifest §4)                                                                                                                                                 |
| ApexClass     | `AXF_CLS_PluggyWebhookSignatureTest`                                                                                                                                  | same                                                                          | **remove** (manifest §4)                                                                                                                                                 |
| ApexClass     | `AXF_CLS_ScheduleReplenishmentStateReader`                                                                                                                            | AXF-103 intermediate design (never committed)                                 | **remove** (manifest §4)                                                                                                                                                 |
| ApexClass ×10 | `SiteLoginController(+Test)`, `SiteRegisterController(+Test)`, `ChangePasswordController(+Test)`, `ForgotPasswordController(+Test)`, `MyProfilePageController(+Test)` | Salesforce Sites samples generated when the `Pluggy_Webhook` site was enabled | **evaluate**: paired with the 17 sample `ApexPage`s (`SiteLogin`, `SiteRegister`, `ChangePassword`, …). Remove pages + classes together, or retain; never one side only. |
| PermissionSet | `Experience_Profile_Manager`                                                                                                                                          | Standard, created by Experience Cloud                                         | retain (platform-owned)                                                                                                                                                  |
| FlexiPage ×14 | `*_UtilityBar`                                                                                                                                                        | Standard app utility bars                                                     | retain (platform-owned)                                                                                                                                                  |
| LWC ×7        | `devedapp__*`                                                                                                                                                         | Developer Edition sample package (`devedapp` namespace)                       | retain; not deletable via destructive changes                                                                                                                            |

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

## 4. Destructive manifest (draft — NOT authorized)

`scripts/cleanup/axf-78/destructiveChanges.xml` removes only the four AXF orphan classes from
§2.1. The Sites sample classes/pages are deliberately excluded until their disposition is decided.

Pre-conditions before Michel is asked to authorize:

1. `scripts/cleanup/axf-78/backup.sh` retrieves the exact components into
   `_bmad-output/backups/axf-78/<timestamp>/` (metadata backup, AC2). Recovery = `sf project
deploy start --source-dir` from that folder.
2. `sf project deploy validate --manifest package.xml --post-destructive-changes
destructiveChanges.xml --test-level RunLocalTests -o AXON_DEV` succeeds (proves no consumer
   references the classes, AC3).
3. Michel replies with the manifest SHA and "authorized" (AC4).

Execution (`--dry-run` removed) then re-runs §2.1 listing and §3 counts (AC5/AC6) and records
deploy id + SHA in this document.

## 5. Out of scope / follow-ups

- Sites sample components: open a decision with Michel (retain vs. remove pages + classes).
- Owner-sync backfill, `AXF_BA/CC_LKP_Account__c` → required/Restrict and
  `AXF_CCI_EXT_ExternalId__c` collision are G9 execution items tracked separately; they are not
  removals and are not in this manifest.
