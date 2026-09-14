/**
 * @description AXF-119: sequencia de encerramento local idempotente, observavel e retomavel —
 * bloqueio seguro sem evidencia de exportacao, revogacao de acessos locais, interrupcao de
 * coleta/publicacao sem chamada ao provedor, expurgo governado por policy (ausencia nao expurga;
 * legal hold bloqueia), evidencia minima e CLOSED terminal; RESULT_UNKNOWN exige reconciliacao;
 * acesso negado e erros sanitizados.
 */
@IsTest
private class ALT_CLS_ClosureOrchestratorTest {
  private static User admin() {
    return [SELECT Id FROM User WHERE Alias = 'axf119a' LIMIT 1];
  }
  private static User outsider() {
    return [SELECT Id FROM User WHERE Alias = 'axf119o' LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    User admin = new User(
      Alias = 'axf119a',
      Email = 'axf119a@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Closure Admin',
      LanguageLocaleKey = 'pt_BR',
      LocaleSidKey = 'pt_BR',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = profileId,
      Username = 'axf119a.' + System.now().getTime() + '@example.invalid'
    );
    User outsider = admin.clone(false, false, false, false);
    outsider.Alias = 'axf119o';
    outsider.LastName = 'Peer Gestor';
    outsider.Username =
      'axf119o.' +
      System.now().getTime() +
      '@example.invalid';
    insert new List<User>{ admin, outsider };
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet permission : [
      SELECT Id
      FROM PermissionSet
      WHERE
        Name IN (
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_FinancialEntry',
          'AXF_PS_PluggyIntegration'
        )
    ]) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = admin.Id,
          PermissionSetId = permission.Id
        )
      );
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = outsider.Id,
          PermissionSetId = permission.Id
        )
      );
    }
    insert assignments;
    grantCollaborationObjectIfInstalled(admin.Id);
  }

  /**
   * AXF-6 may or may not be installed in the validation org; when it is, the operator needs
   * its object permissions (merged into the Gestor permission set by AXF-6) to withdraw grants.
   */
  private static void grantCollaborationObjectIfInstalled(Id userId) {
    Schema.SObjectType grantType = Schema.getGlobalDescribe()
      .get('axf_obj_sharedexpensegrant__c');
    if (grantType == null) {
      return;
    }
    PermissionSet permission = new PermissionSet(
      Name = 'AXF119TestGrants',
      Label = 'AXF119 test grants'
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
  }

  private static Scope makeScope(String key) {
    Scope scope = new Scope();
    scope.holder = new Account(
      Name = 'Holder ' + key,
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
      AXF_FTX_EXI_ClientRequestId__c = 'axf119-' + key
    );
    insert scope.plan;
    return scope;
  }

  private static String code(Exception failure) {
    return ((ALT_CLS_ClosureOrchestrator.ClosureException) failure).code;
  }

  @IsTest
  static void sequenceBlocksWithoutExportThenResumesIdempotentlyToClosed() {
    System.runAs(admin()) {
      Scope scope = makeScope('a');
      ALT_CLS_ClosureOrchestrator service = new ALT_CLS_ClosureOrchestrator();
      Test.startTest();
      ALT_CLS_ClosureOrchestrator.RunView run = service.request(
        scope.holder.Id,
        false
      );
      ALT_CLS_ClosureOrchestrator.RunView same = service.request(
        scope.holder.Id,
        false
      );
      Assert.areEqual(run.runId, same.runId, 'Mesmo escopo = mesmo run.');
      Assert.areEqual('REQUESTED', run.status);
      Assert.areEqual(0, run.progressPercent);

      run = service.advance(run.runId, run.version);
      Assert.areEqual('BLOCKED', run.status);
      Assert.areEqual('EXPORT_PENDING', run.blockReason);
      Assert.areEqual('ATTACH_EXPORT_EVIDENCE', run.nextAction);
      Assert.areEqual('NONE', run.lastCompletedStage);
      Assert.areEqual(1, run.checkpoints.size());

      // Replay of the blocked advance does not execute anything material.
      run = service.advance(run.runId, run.version);
      Assert.areEqual('BLOCKED', run.status);
      Assert.areEqual(2, run.checkpoints.size());
      Assert.areEqual(
        'ACTIVE',
        [
          SELECT AXF_CON_PKL_CollectionState__c
          FROM AXF_OBJ_PluggyConnection__c
          WHERE Id = :scope.connection.Id
        ]
        .AXF_CON_PKL_CollectionState__c,
        'Nada alem da exportacao foi tocado.'
      );

      run = service.attachExportEvidence(
        run.runId,
        '069000000000001AAA',
        run.version
      );
      Assert.areEqual('REQUESTED', run.status);
      run = service.advance(run.runId, run.version);
      Test.stopTest();

      Assert.areEqual(
        'CLOSED',
        run.status,
        run.blockReason + ' ' + ALT_CLS_ClosureOrchestrator.lastStageFailure
      );
      Assert.isTrue(run.closed);
      Assert.areEqual('RETAIN_EVIDENCE', run.lastCompletedStage);
      Assert.areEqual(100, run.progressPercent);
      Assert.areEqual('NONE', run.nextAction);
      Assert.areEqual(
        'NOT_CONFIRMED',
        run.externalRevocation,
        'Pluggy exibida separadamente.'
      );
      Assert.isNotNull(run.correlationId);
      Map<String, ALT_CLS_ClosureOrchestrator.StageCheckpoint> byStage = new Map<String, ALT_CLS_ClosureOrchestrator.StageCheckpoint>();
      for (
        ALT_CLS_ClosureOrchestrator.StageCheckpoint checkpoint : run.checkpoints
      ) {
        byStage.put(checkpoint.stage + ':' + checkpoint.status, checkpoint);
      }
      Assert.isTrue(byStage.containsKey('STOP_COLLECTION:DONE'));
      Assert.areEqual(
        1,
        byStage.get('STOP_COLLECTION:DONE').impact.get('connectionsPaused')
      );
      Assert.areEqual(
        1,
        byStage.get('STOP_COLLECTION:DONE').impact.get('sourcesWithdrawn')
      );
      Assert.isTrue(byStage.containsKey('PURGE:DONE'));
      Assert.areEqual(
        1,
        byStage.get('PURGE:DONE')
          .impact.get('policy.closure.transaction.description.BLOCKED'),
        'Sem policy = sem expurgo.'
      );
      Assert.isNull(
        byStage.get('PURGE:DONE').impact.get('descriptionsPseudonymized')
      );
      Assert.areEqual(
        'PAUSED',
        [
          SELECT AXF_CON_PKL_CollectionState__c
          FROM AXF_OBJ_PluggyConnection__c
          WHERE Id = :scope.connection.Id
        ]
        .AXF_CON_PKL_CollectionState__c
      );
      Assert.areEqual(
        'CUSTODY',
        [
          SELECT AXF_BA_PKL_AvailabilityState__c
          FROM AXF_OBJ_BankAccount__c
          WHERE Id = :scope.bank.Id
        ]
        .AXF_BA_PKL_AvailabilityState__c
      );
      AXF_OBJ_ClosureRun__c stored = [
        SELECT AXF_CLR_TAL_EvidenceSummary__c, AXF_CLR_PKL_Status__c
        FROM AXF_OBJ_ClosureRun__c
        WHERE Id = :run.runId
      ];
      Assert.isTrue(
        stored.AXF_CLR_TAL_EvidenceSummary__c.contains(run.correlationId)
      );
      Assert.isFalse(
        stored.AXF_CLR_TAL_EvidenceSummary__c.contains('Holder a'),
        'Sem PII na evidencia.'
      );
      try {
        service.advance(run.runId, run.version);
        Assert.fail('CLOSED e terminal.');
      } catch (ALT_CLS_ClosureOrchestrator.ClosureException expected) {
        Assert.areEqual('TERMINAL', expected.code);
      }
      Assert.isFalse(
        Database.update(
            new AXF_OBJ_ClosureRun__c(
              Id = run.runId,
              AXF_CLR_PKL_Status__c = 'RUNNING'
            ),
            false
          )
          .isSuccess(),
        'CLOSED nao retrocede.'
      );
      Assert.isFalse(
        Database.delete(new AXF_OBJ_ClosureRun__c(Id = run.runId), false)
          .isSuccess(),
        'Encerramento nao e excluido.'
      );
      Assert.areEqual(1, service.listRuns().size());
    }
  }

  @IsTest
  static void legalHoldBlocksPurgeAndUnknownResultRequiresReconciliation() {
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
        true
      );
      run = service.attachExportEvidence(run.runId, 'evidence-b', run.version);
      Test.startTest();
      run = service.advance(run.runId, run.version);
      Assert.areEqual('BLOCKED', run.status);
      Assert.areEqual('LEGAL_HOLD', run.blockReason);
      Assert.areEqual('RELEASE_LEGAL_HOLD', run.nextAction);
      Assert.areEqual(
        'STOP_COLLECTION',
        run.lastCompletedStage,
        'Etapas anteriores preservadas.'
      );
      Assert.areEqual(
        'Holder b',
        [SELECT Name FROM Account WHERE Id = :scope.holder.Id].Name,
        'Conteudo preservado sob legal hold.'
      );

      // Release the hold, then simulate an unknown result on the purge stage.
      update new AXF_OBJ_ClosureRun__c(
        Id = run.runId,
        AXF_CLR_BOL_LegalHold__c = false
      );
      run = service.read(run.runId);
      ALT_CLS_ClosureOrchestrator.simulateUnknownAt = 'PURGE';
      run = service.advance(run.runId, run.version);
      Assert.areEqual('RESULT_UNKNOWN', run.status);
      Assert.isTrue(run.canReconcile);
      Assert.isFalse(run.canAdvance);
      try {
        service.advance(run.runId, run.version);
        Assert.fail('Etapa material nao se repete sem reconciliar.');
      } catch (ALT_CLS_ClosureOrchestrator.ClosureException expected) {
        Assert.areEqual('RECONCILE_FIRST', expected.code);
      }
      ALT_CLS_ClosureOrchestrator.simulateUnknownAt = null;
      run = AXF_CLS_CTRL_ClosureRun.reconcile(run.runId, run.version);
      Assert.areEqual('REQUESTED', run.status);
      try {
        service.reconcile(run.runId, run.version);
        Assert.fail('Nada a reconciliar.');
      } catch (ALT_CLS_ClosureOrchestrator.ClosureException expected) {
        Assert.areEqual('NOT_RECONCILABLE', expected.code);
      }
      try {
        AXF_CLS_CTRL_ClosureRun.advance(run.runId, 1);
        Assert.fail('Versao obsoleta conflita.');
      } catch (AuraHandledException expected) {
        Assert.areEqual('CONFLICT', expected.getMessage());
      }
      run = AXF_CLS_CTRL_ClosureRun.advance(run.runId, run.version);
      Test.stopTest();
      Assert.areEqual(
        'CLOSED',
        run.status,
        run.blockReason + ' ' + ALT_CLS_ClosureOrchestrator.lastStageFailure
      );
      Assert.isTrue(
        run.checkpoints.size() >= 6,
        'Checkpoints acumulam por tentativa.'
      );
      Boolean deferred = false;
      for (
        ALT_CLS_ClosureOrchestrator.StageCheckpoint checkpoint : run.checkpoints
      ) {
        if (checkpoint.stage == 'PURGE' && checkpoint.status == 'DONE') {
          deferred = checkpoint.impact.containsKey(
            'policy.' +
              ALT_CLS_ClosureOrchestrator.DOMAIN_TRANSACTION_DESCRIPTION +
              '.DUE_LATER'
          );
        }
      }
      Assert.isTrue(
        deferred,
        'Policy elegivel mas fora do prazo nao expurga antecipadamente.'
      );
      AXF_OBJ_ClosureRun__c stored = [
        SELECT AXF_CLR_TXT_PolicyVersion__c
        FROM AXF_OBJ_ClosureRun__c
        WHERE Id = :run.runId
      ];
      Assert.isTrue(
        stored.AXF_CLR_TXT_PolicyVersion__c.contains('1.0.0'),
        'Receipt da policy registrado.'
      );
    }
  }

  @IsTest
  static void pseudonymizationTokenIsStableAndIrreversible() {
    System.runAs(admin()) {
      Scope scope = makeScope('c');
      scope.plan.AXF_FTX_TXT_Description__c = 'Aluguel sala 12 - Maria';
      update scope.plan;
      insert new AXF_OBJ_BankAccountTransaction__c(
        AXF_BAT_MDR_BankAccount__c = scope.bank.Id,
        AXF_BAT_EXI_SourceKey__c = 'bat-c-' + System.now().getTime(),
        AXF_BAT_PKL_Source__c = 'MANUAL',
        AXF_BAT_DAT_Date__c = Date.today(),
        AXF_BAT_NUM_Magnitude__c = 10,
        AXF_BAT_PKL_Direction__c = 'DEBIT',
        AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_BAT_TXT_Description__c = 'PIX Joao',
        AXF_BAT_NUM_Version__c = 0
      );
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
      run = service.attachExportEvidence(run.runId, 'evidence-c', run.version);
      // Retention window (1 day) elapsed since the closure request.
      Test.setCreatedDate(run.runId, Datetime.now().addDays(-3));
      Test.startTest();
      run = service.advance(run.runId, run.version);
      Test.stopTest();
      Assert.areEqual(
        'CLOSED',
        run.status,
        run.blockReason + ' ' + ALT_CLS_ClosureOrchestrator.lastStageFailure
      );
      String description = [
        SELECT AXF_FTX_TXT_Description__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id = :scope.plan.Id
      ]
      .AXF_FTX_TXT_Description__c;
      Assert.isTrue(description.startsWith('pseudo:'), description);
      Assert.isFalse(description.contains('Maria'));
      AXF_OBJ_BankAccountTransaction__c fact = [
        SELECT AXF_BAT_TXT_Description__c, AXF_BAT_NUM_Magnitude__c
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE AXF_BAT_MDR_BankAccount__c = :scope.bank.Id
      ];
      Assert.isTrue(fact.AXF_BAT_TXT_Description__c.startsWith('pseudo:'));
      Assert.areEqual(
        10,
        fact.AXF_BAT_NUM_Magnitude__c,
        'Valores originais preservados.'
      );
      Boolean pseudonymized = false;
      for (
        ALT_CLS_ClosureOrchestrator.StageCheckpoint checkpoint : run.checkpoints
      ) {
        if (checkpoint.stage == 'PURGE') {
          pseudonymized =
            checkpoint.impact.get('descriptionsPseudonymized') == 2;
        }
      }
      Assert.isTrue(pseudonymized, 'Impacto observavel por etapa.');
    }
  }

  @IsTest
  static void unauthorizedUsersAreDeniedWithoutDisclosure() {
    Scope scope;
    ALT_CLS_ClosureOrchestrator.RunView run;
    System.runAs(admin()) {
      scope = makeScope('d');
      run = new ALT_CLS_ClosureOrchestrator().request(scope.holder.Id, false);
    }
    System.runAs(outsider()) {
      ALT_CLS_ClosureOrchestrator service = new ALT_CLS_ClosureOrchestrator();
      for (Integer i = 0; i < 3; i++) {
        try {
          if (i == 0) {
            service.request(scope.holder.Id, false);
          } else if (i == 1) {
            service.advance(run.runId, run.version);
          } else {
            service.read(run.runId);
          }
          Assert.fail('Gestor sem acesso ao escopo: ' + i);
        } catch (ALT_CLS_ClosureOrchestrator.ClosureException expected) {
          Assert.areEqual('NOT_ACCESSIBLE', expected.code);
        }
      }
      Assert.areEqual(0, service.listRuns().size());
    }
    Test.startTest();
    System.runAs(admin()) {
      Assert.isTrue(AXF_CLS_CTRL_ClosureRun.canClose());
      Assert.areEqual(1, AXF_CLS_CTRL_ClosureRun.listRuns().size());
      ALT_CLS_ClosureOrchestrator.RunView view = AXF_CLS_CTRL_ClosureRun.read(
        run.runId
      );
      Assert.areEqual(run.runId, view.runId);
      try {
        AXF_CLS_CTRL_ClosureRun.reconcile(run.runId, view.version);
        Assert.fail('Nada a reconciliar.');
      } catch (AuraHandledException expected) {
        Assert.areEqual('NOT_RECONCILABLE', expected.getMessage());
      }
      try {
        AXF_CLS_CTRL_ClosureRun.attachExportEvidence(
          run.runId,
          '',
          view.version
        );
        Assert.fail('Evidencia vazia.');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', expected.getMessage());
      }
      try {
        AXF_CLS_CTRL_ClosureRun.request(null, false);
        Assert.fail('Escopo ausente.');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', expected.getMessage());
      }
      Assert.isFalse(AXF_CLS_CTRL_ClosureRun.getHolders().isEmpty());
      view = AXF_CLS_CTRL_ClosureRun.advance(run.runId, view.version);
      Assert.areEqual('BLOCKED', view.status);
      view = AXF_CLS_CTRL_ClosureRun.attachExportEvidence(
        run.runId,
        'evidence-d',
        view.version
      );
      Assert.areEqual('REQUESTED', view.status);
    }
    Test.stopTest();
  }
}
