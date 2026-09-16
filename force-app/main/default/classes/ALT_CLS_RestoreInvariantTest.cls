/**
 * @description AXF-121: the non-reactivation mark is minimal proof of the lifecycle, carrying no
 * private content, and the restore guard refuses to reactivate a closed scope. The negative case is
 * explicit: a restored record found in a backup of a closed scope stays inactive, and refusal is
 * also the safe answer when the proof is absent, does not belong to the scope, or the closure is
 * still running.
 *
 * These tests exercise the invariant and the integration point. They are **not** an end-to-end
 * restore: the backup vendor and mechanism are `Deferred` (G9-3), so the real restore rehearsal
 * remains a production gate tracked in AXF-79, and a simulated adapter would not substitute for it.
 */
@IsTest
private class ALT_CLS_RestoreInvariantTest {
  private static final String PRIVATE_HOLDER = 'Titular Confidencial Alfa';
  private static final String PRIVATE_DESCRIPTION = 'Consulta cardiologia Maria Silva';

  private static User admin() {
    return [SELECT Id FROM User WHERE Alias = 'axf121a' LIMIT 1];
  }

  private static User nobody() {
    return [SELECT Id FROM User WHERE Alias = 'axf121n' LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    User admin = new User(
      Alias = 'axf121a',
      Email = 'axf121a@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Restore Admin',
      LanguageLocaleKey = 'pt_BR',
      LocaleSidKey = 'pt_BR',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = profileId,
      Username = 'axf121a.' + System.now().getTime() + '@example.invalid'
    );
    User nobody = admin.clone(false, false, false, false);
    nobody.Alias = 'axf121n';
    nobody.LastName = 'No Capability';
    nobody.Username = 'axf121n.' + System.now().getTime() + '@example.invalid';
    insert new List<User>{ admin, nobody };
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet permission : [
      SELECT Id
      FROM PermissionSet
      WHERE
        Name IN (
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_FinancialEntry',
          'AXF_PS_PluggyIntegration',
          'AXF_PS_Realization'
        )
    ]) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = admin.Id,
          PermissionSetId = permission.Id
        )
      );
    }
    // The closure path reads realization allocations to keep referenced facts as evidence, so the
    // operator carries the realization capability exactly as AXF-119's own tests require.
    PermissionSet realize = new PermissionSet(
      Name = 'AXF121TestRealize',
      Label = 'AXF121 realization capability'
    );
    insert realize;
    insert new SetupEntityAccess(
      ParentId = realize.Id,
      SetupEntityId = [
        SELECT Id
        FROM CustomPermission
        WHERE DeveloperName = 'AXF_CanRealize'
        LIMIT 1
      ]
      .Id
    );
    assignments.add(
      new PermissionSetAssignment(
        AssigneeId = admin.Id,
        PermissionSetId = realize.Id
      )
    );
    insert assignments;
    grantCollaborationObjectIfInstalled(admin.Id);
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new AXF_ReportCurrencyPref__c(
        SetupOwnerId = UserInfo.getOrganizationId(),
        AXF_RCP_TXT_IsoCode__c = 'BRL'
      );
    }
  }

  /**
   * AXF-6 may or may not be installed in the validation org; when it is, the operator needs its
   * object permissions (merged into the Gestor permission set by AXF-6) so the closure can
   * withdraw the local collaboration grants.
   */
  private static void grantCollaborationObjectIfInstalled(Id userId) {
    Schema.SObjectType grantType = Schema.getGlobalDescribe()
      .get('axf_obj_sharedexpensegrant__c');
    if (grantType == null) {
      return;
    }
    PermissionSet permission = new PermissionSet(
      Name = 'AXF121TestGrants',
      Label = 'AXF121 test grants'
    );
    insert permission;
    insert new ObjectPermissions(
      ParentId = permission.Id,
      SobjectType = 'AXF_OBJ_SharedExpenseGrant__c',
      PermissionsRead = true,
      PermissionsCreate = true,
      PermissionsEdit = true
    );
    List<FieldPermissions> fields = new List<FieldPermissions>();
    for (
      String field : new List<String>{
        'AXF_SEG_DT_RevokedAt__c',
        'AXF_SEG_LKP_RevokedBy__c',
        'AXF_SEG_LKP_Collaborator__c',
        'AXF_SEG_NUM_Version__c',
        'AXF_SEG_TXT_LastRequestId__c'
      }
    ) {
      fields.add(
        new FieldPermissions(
          ParentId = permission.Id,
          SobjectType = 'AXF_OBJ_SharedExpenseGrant__c',
          Field = 'AXF_OBJ_SharedExpenseGrant__c.' + field,
          PermissionsRead = true,
          PermissionsEdit = true
        )
      );
    }
    insert fields;
    insert new PermissionSetAssignment(
      AssigneeId = userId,
      PermissionSetId = permission.Id
    );
  }

  private class Scope {
    Account holder;
    AXF_OBJ_BankAccount__c bank;
    AXF_OBJ_PluggyConnection__c connection;
    AXF_OBJ_FinancialTransaction__c plan;
    AXF_OBJ_BankAccountTransaction__c fact;
  }

  private static Scope makeScope(String key) {
    Scope scope = new Scope();
    scope.holder = new Account(
      Name = PRIVATE_HOLDER + ' ' + key,
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert scope.holder;
    scope.bank = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = scope.holder.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_InstitutionName__c = 'Banco ' + key,
      AXF_BA_TXT_NumberMasked__c = '****' + key,
      AXF_BA_EXI_ManualKey__c = 'manual-' + key + '-' + System.now().getTime(),
      AXF_BA_NUM_Version__c = 0
    );
    insert scope.bank;
    scope.connection = new AXF_OBJ_PluggyConnection__c(
      AXF_CON_LKP_Account__c = scope.holder.Id,
      AXF_CON_PKL_CollectionState__c = 'ACTIVE',
      AXF_CON_PKL_ConsentState__c = 'ACTIVE',
      AXF_CON_EXI_PluggyItemId__c = 'item-' + key + '-' + System.now().getTime()
    );
    insert scope.connection;
    scope.plan = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = scope.holder.Id,
      AXF_FTX_NUM_Magnitude__c = 100,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = Date.today(),
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_NUM_Version__c = 0,
      AXF_FTX_TXT_Description__c = PRIVATE_DESCRIPTION,
      AXF_FTX_EXI_ClientRequestId__c = 'axf121-' +
        key +
        '-' +
        System.now().getTime()
    );
    insert scope.plan;
    scope.fact = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = scope.bank.Id,
      AXF_BAT_EXI_SourceKey__c = 'bat-' + key + '-' + System.now().getTime(),
      AXF_BAT_PKL_Source__c = 'MANUAL',
      AXF_BAT_DAT_Date__c = Date.today(),
      AXF_BAT_NUM_Magnitude__c = 10,
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_TXT_Description__c = PRIVATE_DESCRIPTION,
      AXF_BAT_NUM_Version__c = 0
    );
    insert scope.fact;
    return scope;
  }

  /** Drives a scope to its terminal state; no retention policy applies, so nothing is purged. */
  private static ALT_CLS_ClosureOrchestrator.RunView closeScope(Scope scope) {
    ALT_CLS_ClosureOrchestrator service = new ALT_CLS_ClosureOrchestrator();
    ALT_CLS_ClosureOrchestrator.RunView run = service.request(
      scope.holder.Id,
      false
    );
    run = service.attachExportEvidence(
      run.runId,
      '069000000000121AAA',
      run.version
    );
    return service.advance(run.runId, run.version);
  }

  private static String closureCode(Exception failure) {
    return ((ALT_CLS_ClosureOrchestrator.ClosureException) failure).code;
  }

  @IsTest
  static void markIsContentFreeAndTamperEvident() {
    System.runAs(admin()) {
      Scope scope = makeScope('a');
      Test.startTest();
      ALT_CLS_ClosureOrchestrator.RunView run = closeScope(scope);
      Test.stopTest();
      Assert.areEqual(
        'CLOSED',
        run.status,
        run.blockReason + ' ' + ALT_CLS_ClosureOrchestrator.lastStageFailure
      );

      String mark = [
        SELECT AXF_CLR_TAL_NonReactivationMark__c
        FROM AXF_OBJ_ClosureRun__c
        WHERE Id = :run.runId
      ]
      .AXF_CLR_TAL_NonReactivationMark__c;
      Assert.isNotNull(mark, 'The closure marks what must not be reactivated.');
      Map<String, Object> proof = (Map<String, Object>) JSON.deserializeUntyped(
        mark
      );
      Assert.areEqual(
        new Set<String>{
          'schemaVersion',
          'scopeKey',
          'correlationId',
          'policyVersion',
          'closedAt',
          'fingerprint'
        },
        proof.keySet(),
        'The mark holds nothing beyond the allowlisted, content-free keys.'
      );
      Assert.areEqual(String.valueOf(scope.holder.Id), proof.get('scopeKey'));
      Assert.areEqual(run.correlationId, proof.get('correlationId'));
      for (
        String secret : new List<String>{ PRIVATE_HOLDER, PRIVATE_DESCRIPTION }
      ) {
        Assert.isFalse(
          mark.contains(secret),
          'Minimal evidence never reconstructs private content: ' + secret
        );
      }
      // Terminal rule: the mark of a closed closure is evidence and cannot be rewritten.
      Assert.isFalse(
        Database.update(
            new AXF_OBJ_ClosureRun__c(
              Id = run.runId,
              AXF_CLR_TAL_NonReactivationMark__c = '{}'
            ),
            false
          )
          .isSuccess(),
        'The non-reactivation mark of a closed closure is immutable.'
      );
    }
  }

  @IsTest
  static void restoredScopeOfAClosedClosureIsNotReactivated() {
    System.runAs(admin()) {
      Scope scope = makeScope('b');
      ALT_CLS_RetentionPolicy.policyFixtures = new List<AXF_CMT_RetentionPolicy__mdt>{
        new AXF_CMT_RetentionPolicy__mdt(
          DeveloperName = 'Closure_Description',
          MasterLabel = 'Closure description',
          AXF_RPT_TXT_Domain__c = ALT_CLS_ClosureOrchestrator.DOMAIN_TRANSACTION_DESCRIPTION,
          AXF_RPT_TXT_PurgeTrigger__c = 'CLOSURE',
          AXF_RPT_NUM_RetentionDays__c = 1,
          AXF_RPT_BOL_Enabled__c = true,
          AXF_RPT_TXT_Version__c = '1.0.0'
        )
      };
      ALT_CLS_ClosureOrchestrator service = new ALT_CLS_ClosureOrchestrator();
      ALT_CLS_ClosureOrchestrator.RunView run = service.request(
        scope.holder.Id,
        false
      );
      run = service.attachExportEvidence(
        run.runId,
        '069000000000121BBB',
        run.version
      );
      // The retention window (1 day) elapsed since the closure request, so the purge stage
      // pseudonymized the descriptions instead of keeping them.
      Test.setCreatedDate(run.runId, Datetime.now().addDays(-3));
      Test.startTest();
      run = service.advance(run.runId, run.version);
      Test.stopTest();
      Assert.areEqual(
        'CLOSED',
        run.status,
        run.blockReason + ' ' + ALT_CLS_ClosureOrchestrator.lastStageFailure
      );
      Assert.isTrue(
        [
            SELECT AXF_FTX_TXT_Description__c
            FROM AXF_OBJ_FinancialTransaction__c
            WHERE Id = :scope.plan.Id
          ]
          .AXF_FTX_TXT_Description__c.startsWith('pseudo:'),
        'The closed scope holds pseudonymized content.'
      );

      // A later restore finds this scope's rows in the backup and must ask before reactivating.
      List<ALT_CLS_RestoreInvariant.Assessment> verdicts = new ALT_CLS_RestoreInvariant()
        .assess(new List<Id>{ scope.holder.Id });
      Assert.areEqual(1, verdicts.size());
      ALT_CLS_RestoreInvariant.Assessment verdict = verdicts[0];
      Assert.areEqual(scope.holder.Id, verdict.holderId);
      Assert.areEqual('NOT_REACTIVATED', verdict.verdict);
      Assert.isFalse(
        verdict.reactivationAllowed,
        'Deleted or pseudonymized data is not reactivated in the active service.'
      );
      Assert.areEqual('CLOSED_SCOPE', verdict.reason);
      Assert.isTrue(
        verdict.lifecycleProof.contains(run.correlationId),
        'Minimal evidence preserves the proof of the lifecycle.'
      );
      for (
        String secret : new List<String>{ PRIVATE_HOLDER, PRIVATE_DESCRIPTION }
      ) {
        Assert.isFalse(
          verdict.lifecycleProof.contains(secret),
          'The proof does not rebuild private content: ' + secret
        );
      }
      // The guard decides; it never reactivates anything by itself.
      Assert.areEqual(
        'CUSTODY',
        [
          SELECT AXF_BA_PKL_AvailabilityState__c
          FROM AXF_OBJ_BankAccount__c
          WHERE Id = :scope.bank.Id
        ]
        .AXF_BA_PKL_AvailabilityState__c,
        'The restored source is not put back in service.'
      );
      Assert.areEqual(
        'PAUSED',
        [
          SELECT AXF_CON_PKL_CollectionState__c
          FROM AXF_OBJ_PluggyConnection__c
          WHERE Id = :scope.connection.Id
        ]
        .AXF_CON_PKL_CollectionState__c,
        'Collection is not restarted.'
      );
    }
  }

  @IsTest
  static void neverClosedScopeIsAllowedAndRunningClosureIsRefused() {
    System.runAs(admin()) {
      Scope untouched = makeScope('c');
      Scope running = makeScope('d');
      ALT_CLS_ClosureOrchestrator.RunView inFlight = new ALT_CLS_ClosureOrchestrator()
        .request(running.holder.Id, false);
      Assert.areEqual('REQUESTED', inFlight.status);

      Test.startTest();
      List<ALT_CLS_RestoreInvariant.Assessment> verdicts = new ALT_CLS_RestoreInvariant()
        .assess(
          new List<Id>{
            untouched.holder.Id,
            running.holder.Id,
            untouched.holder.Id
          }
        );
      Test.stopTest();
      Assert.areEqual(3, verdicts.size(), 'One assessment per restored scope.');
      Assert.areEqual(untouched.holder.Id, verdicts[0].holderId);
      Assert.areEqual('REACTIVATION_ALLOWED', verdicts[0].verdict);
      Assert.areEqual('NEVER_CLOSED', verdicts[0].reason);
      Assert.isTrue(verdicts[0].reactivationAllowed);
      Assert.isNull(verdicts[0].lifecycleProof);
      Assert.areEqual('CLOSURE_IN_PROGRESS', verdicts[1].reason);
      Assert.isFalse(
        verdicts[1].reactivationAllowed,
        'An in-flight closure is never a reactivation permit.'
      );
      Assert.areEqual(
        untouched.holder.Id,
        verdicts[2].holderId,
        'Input order is preserved.'
      );
    }
  }

  @IsTest
  static void untrustedProofFailsClosed() {
    System.runAs(admin()) {
      Scope scope = makeScope('e');
      String scopeKey = String.valueOf(scope.holder.Id);
      String valid = ALT_CLS_RestoreInvariant.mark(
        scopeKey,
        'closure-correlation-e',
        '1.0.0',
        Datetime.now()
      );
      AXF_OBJ_ClosureRun__c base = new AXF_OBJ_ClosureRun__c(
        AXF_CLR_EXI_ScopeKey__c = scopeKey,
        AXF_CLR_PKL_Status__c = 'CLOSED'
      );

      // A closure that reached CLOSED before this story shipped has no mark: refuse.
      AXF_OBJ_ClosureRun__c unmarked = base.clone(false, true, false, false);
      unmarked.AXF_CLR_TAL_NonReactivationMark__c = null;
      Assert.areEqual(
        'MARK_MISSING',
        ALT_CLS_RestoreInvariant.assessOne(scopeKey, unmarked).reason
      );

      // A mark that belongs to another scope is a spliced proof: refuse.
      AXF_OBJ_ClosureRun__c spliced = base.clone(false, true, false, false);
      spliced.AXF_CLR_TAL_NonReactivationMark__c = valid;
      Assert.areEqual(
        'MARK_MISMATCH',
        ALT_CLS_RestoreInvariant.assessOne('001000000000121AAA', spliced).reason
      );

      // A proof carrying a key outside the allowlist could smuggle private content: refuse.
      AXF_OBJ_ClosureRun__c smuggled = base.clone(false, true, false, false);
      smuggled.AXF_CLR_TAL_NonReactivationMark__c = JSON.serialize(
        new Map<String, Object>{
          'schemaVersion' => 'axf-non-reactivation@1.0.0',
          'scopeKey' => scopeKey,
          'description' => PRIVATE_DESCRIPTION
        }
      );
      Assert.areEqual(
        'MARK_MISMATCH',
        ALT_CLS_RestoreInvariant.assessOne(scopeKey, smuggled).reason
      );

      // A proof whose digest no longer matches its own fields was altered: refuse.
      AXF_OBJ_ClosureRun__c altered = base.clone(false, true, false, false);
      altered.AXF_CLR_TAL_NonReactivationMark__c = valid.replace(
        'closure-correlation-e',
        'closure-correlation-x'
      );
      Assert.areEqual(
        'MARK_MISMATCH',
        ALT_CLS_RestoreInvariant.assessOne(scopeKey, altered).reason
      );

      // The intact proof of this very scope is the only case that preserves the lifecycle.
      AXF_OBJ_ClosureRun__c intact = base.clone(false, true, false, false);
      intact.AXF_CLR_TAL_NonReactivationMark__c = valid;
      ALT_CLS_RestoreInvariant.Assessment accepted = ALT_CLS_RestoreInvariant.assessOne(
        scopeKey,
        intact
      );
      Assert.areEqual('CLOSED_SCOPE', accepted.reason);
      Assert.areEqual(valid, accepted.lifecycleProof);
      Assert.isFalse(accepted.reactivationAllowed);
    }
  }

  @IsTest
  static void accessAndInputAreRefused() {
    Scope scope;
    System.runAs(admin()) {
      scope = makeScope('f');
      Test.startTest();
      try {
        new ALT_CLS_RestoreInvariant().assess(null);
        Assert.fail('A safety gate never answers a null restore.');
      } catch (ALT_CLS_ClosureOrchestrator.ClosureException expected) {
        Assert.areEqual('INVALID_INPUT', closureCode(expected));
      }
      try {
        new ALT_CLS_RestoreInvariant()
          .assess(new List<Id>{ scope.holder.Id, null });
        Assert.fail('An unnamed scope cannot be assessed.');
      } catch (ALT_CLS_ClosureOrchestrator.ClosureException expected) {
        Assert.areEqual('INVALID_INPUT', closureCode(expected));
      }
      Test.stopTest();
    }
    System.runAs(nobody()) {
      Test.startTest();
      try {
        new ALT_CLS_RestoreInvariant().assess(new List<Id>{ scope.holder.Id });
        Assert.fail('Without the closure capability there is no invariant.');
      } catch (ALT_CLS_ClosureOrchestrator.ClosureException expected) {
        Assert.areEqual('FORBIDDEN', closureCode(expected));
      }
      Test.stopTest();
    }
  }
}
