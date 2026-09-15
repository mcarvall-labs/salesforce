/**
 * @description AXF-141: reversal with reason creates an immutable compensating allocation linked
 * to the original, restores the derived net of plan and source, replays by key, conflicts on a
 * divergent payload, never reverses twice, and reversing an ACTUAL_ONLY realization invents no
 * forecast debt. Nothing confirmed is edited or deleted.
 */
@IsTest(isParallel=false)
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class ALT_CLS_ReconciliationReversalTest {
  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    List<User> users = new List<User>();
    for (String alias : new List<String>{ 'axf141g', 'axf141p', 'axf141n' }) {
      users.add(
        new User(
          Alias = alias,
          Email = alias + '@example.invalid',
          EmailEncodingKey = 'UTF-8',
          LastName = 'User ' + alias,
          LanguageLocaleKey = 'pt_BR',
          LocaleSidKey = 'pt_BR',
          TimeZoneSidKey = 'America/Sao_Paulo',
          ProfileId = profileId,
          Username = alias + '.' + System.now().getTime() + '@example.invalid'
        )
      );
    }
    insert users;
    Map<String, Id> permissionSets = new Map<String, Id>();
    for (PermissionSet permission : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE
        Name IN (
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_FinancialEntry',
          'AXF_PS_Realization',
          'AXF_PS_Participante'
        )
    ]) {
      permissionSets.put(permission.Name, permission.Id);
    }
    Assert.areEqual(4, permissionSets.size(), 'permission sets must exist');
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (Integer i = 0; i < 2; i++) {
      for (
        String name : new List<String>{
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_FinancialEntry',
          'AXF_PS_Realization'
        }
      ) {
        assignments.add(
          new PermissionSetAssignment(
            AssigneeId = users[i].Id,
            PermissionSetId = permissionSets.get(name)
          )
        );
      }
    }
    assignments.add(
      new PermissionSetAssignment(
        AssigneeId = users[2].Id,
        PermissionSetId = permissionSets.get('AXF_PS_Participante')
      )
    );
    insert assignments;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new AXF_ReportCurrencyPref__c(
        SetupOwnerId = UserInfo.getOrganizationId(),
        AXF_RCP_TXT_IsoCode__c = 'BRL'
      );
    }
  }

  private class Fixture {
    public Account holder;
    public AXF_OBJ_BankAccount__c bank;
    public AXF_OBJ_BankAccountTransaction__c fact;
    public AXF_OBJ_FinancialTransaction__c plan;
    public Id allocationId;
  }

  /** Holder, available bank, POSTED fact of 100, plan of 100 and one application of 60 (BANK source). */
  private static Fixture fixture(String key, Id targetOrNull) {
    Fixture f = new Fixture();
    f.holder = new Account(
      Name = 'Holder 141 ' + key,
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert f.holder;
    f.bank = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = f.holder.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL'
    );
    insert f.bank;
    f.fact = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = f.bank.Id,
      AXF_BAT_NUM_Magnitude__c = 100,
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_DAT_Date__c = Date.today(),
      AXF_BAT_TXT_Description__c = 'Fact ' + key,
      AXF_BAT_EXI_SourceKey__c = 'axf141-' + key,
      AXF_BAT_PKL_Source__c = 'CSV',
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_NUM_Version__c = 0
    );
    insert f.fact;
    ALT_CLS_RealizationService.Input apply = new ALT_CLS_RealizationService.Input();
    apply.sourceId = f.fact.Id;
    apply.sourceKind = 'BANK';
    apply.sourceVersion = 0;
    apply.amount = 60;
    apply.recognitionDate = Date.today();
    apply.operationKey = 'axf141-apply-' + key;
    if (targetOrNull == null && key != 'actual') {
      f.plan = new AXF_OBJ_FinancialTransaction__c(
        AXF_FTX_LKP_Account__c = f.holder.Id,
        AXF_FTX_NUM_Magnitude__c = 100,
        AXF_FTX_PKL_Direction__c = 'DEBIT',
        AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_FTX_DAT_PurchaseDate__c = Date.today(),
        AXF_FTX_TXT_Description__c = 'Plan ' + key,
        AXF_FTX_PKL_Status__c = 'PLANNED',
        AXF_FTX_NUM_Version__c = 0,
        AXF_FTX_EXI_ClientRequestId__c = 'ftx-141-' + key
      );
      insert f.plan;
      apply.targetId = f.plan.Id;
      apply.targetVersion = 0;
    } else {
      // ACTUAL_ONLY plan born from the fact (no forecast).
      apply.accountId = f.holder.Id;
      apply.currencyIso = 'BRL';
      apply.direction = 'DEBIT';
    }
    f.allocationId = new ALT_CLS_RealizationService().apply(apply);
    return f;
  }

  private static ALT_CLS_ReconciliationReversalService.Input input(
    Id allocationId,
    Decimal version,
    String reason,
    String note,
    String key
  ) {
    ALT_CLS_ReconciliationReversalService.Input i = new ALT_CLS_ReconciliationReversalService.Input();
    i.allocationId = allocationId;
    i.expectedVersion = version;
    i.reasonCode = reason;
    i.reasonNote = note;
    i.operationKey = 'axf141-' + key;
    return i;
  }

  private static String failure(ALT_CLS_ReconciliationReversalService.Input i) {
    try {
      new ALT_CLS_ReconciliationReversalService().reverse(i);
      return null;
    } catch (ALT_CLS_ReconciliationReversalService.ReversalException expected) {
      return expected.getMessage();
    }
  }

  private static ALT_CLS_ReconciliationReversalService.ListQuery query(
    Id accountId
  ) {
    ALT_CLS_ReconciliationReversalService.ListQuery q = new ALT_CLS_ReconciliationReversalService.ListQuery();
    q.accountId = accountId;
    return q;
  }

  @IsTest
  static void reversalWithReasonCompensatesImmutablyAndRestoresDerivedNet() {
    System.runAs(byAlias('axf141g')) {
      Fixture f = fixture('basic', null);
      ALT_CLS_ReconciliationReversalService service = new ALT_CLS_ReconciliationReversalService();
      ALT_CLS_ReconciliationReversalService.AllocationPage before = service.listAllocations(
        query(f.holder.Id)
      );
      Test.startTest();
      ALT_CLS_ReconciliationReversalService.Result reversed = service.reverse(
        input(f.allocationId, 1, 'WRONG_TARGET', '  wrong invoice  ', 'r1')
      );
      ALT_CLS_ReconciliationReversalService.Result replayed = service.reverse(
        input(f.allocationId, 1, 'WRONG_TARGET', '  wrong invoice  ', 'r1')
      );
      String divergentReason = failure(
        input(f.allocationId, 1, 'USER_ERROR', 'wrong invoice', 'r1')
      );
      String divergentNote = failure(
        input(f.allocationId, 1, 'WRONG_TARGET', 'another note', 'r1')
      );
      String again = failure(
        input(f.allocationId, 2, 'WRONG_TARGET', null, 'r2')
      );
      Test.stopTest();

      Assert.areEqual(1, before.items.size());
      Assert.isNull(before.items[0].reversalId, 'not reversed yet');
      Assert.areEqual(60, before.items[0].amount);
      Assert.areEqual('BANK', before.items[0].sourceKind);
      Assert.areEqual(f.fact.Id, before.items[0].sourceId);
      Assert.isFalse(reversed.replayed);
      Assert.areEqual(f.allocationId, reversed.originalId);
      Assert.areEqual('WRONG_TARGET', reversed.reasonCode);
      Assert.areEqual(60, reversed.amount);
      Assert.areEqual(100, reversed.plannedAfter);
      Assert.areEqual(
        0,
        reversed.realizedAfter,
        'net contribution back to zero'
      );
      Assert.areEqual(100, reversed.residualAfter);
      Assert.areEqual('NONE', reversed.stateAfter);
      Assert.areEqual(2, reversed.targetVersionAfter, 'apply + reverse');
      Assert.areEqual(
        100,
        reversed.sourceResidualAfter,
        'source capacity restored'
      );
      Assert.isTrue(
        reversed.boundaries.isEmpty(),
        'standalone plan: no AXF-104 boundary'
      );
      Assert.isTrue(replayed.replayed, 'same key and payload replays');
      Assert.areEqual(reversed.reversalId, replayed.reversalId);
      Assert.areEqual(
        'CONFLICT',
        divergentReason,
        'reason is part of the payload'
      );
      Assert.areEqual('CONFLICT', divergentNote, 'note is part of the payload');
      Assert.areEqual('ALREADY_REVERSED', again, 'no second compensation');
      ALT_CLS_ReconciliationReversalService.Result prior = service.priorReversal(
        f.allocationId
      );
      Assert.areEqual(reversed.reversalId, prior.reversalId);
      Assert.areEqual('WRONG_TARGET', prior.reasonCode);
      List<AXF_OBJ_ReconciliationAllocation__c> effects = [
        SELECT
          Id,
          AXF_RA_PKL_Kind__c,
          AXF_RA_LKP_OriginalAllocation__c,
          AXF_RA_NUM_Magnitude__c,
          AXF_RA_LKP_BankTransaction__c,
          AXF_RA_LKP_FinancialTransaction__c,
          AXF_RA_PKL_ReversalReason__c,
          AXF_RA_TXT_ReversalNote__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        ORDER BY CreatedDate, Id
      ];
      Assert.areEqual(2, effects.size(), 'one application, one compensation');
      Assert.areEqual('APPLICATION', effects[0].AXF_RA_PKL_Kind__c);
      Assert.isNull(
        effects[0].AXF_RA_PKL_ReversalReason__c,
        'original untouched'
      );
      Assert.areEqual('REVERSAL', effects[1].AXF_RA_PKL_Kind__c);
      Assert.areEqual(
        f.allocationId,
        effects[1].AXF_RA_LKP_OriginalAllocation__c
      );
      Assert.areEqual(60, effects[1].AXF_RA_NUM_Magnitude__c);
      Assert.areEqual(f.fact.Id, effects[1].AXF_RA_LKP_BankTransaction__c);
      Assert.areEqual(f.plan.Id, effects[1].AXF_RA_LKP_FinancialTransaction__c);
      Assert.areEqual('WRONG_TARGET', effects[1].AXF_RA_PKL_ReversalReason__c);
      Assert.areEqual(
        'wrong invoice',
        effects[1].AXF_RA_TXT_ReversalNote__c,
        'trimmed'
      );
      // Immutable: neither the compensation nor its reason can be edited or deleted.
      try {
        effects[1].AXF_RA_TXT_ReversalNote__c = 'edited';
        update effects[1];
        Assert.fail('compensation is immutable');
      } catch (DmlException expected) {
        Assert.isTrue(
          expected.getMessage().contains('realization service'),
          expected.getMessage()
        );
      }
      try {
        delete effects[1];
        Assert.fail('history cannot be deleted');
      } catch (DmlException expected) {
        Assert.isNotNull(expected);
      }
      ALT_CLS_ReconciliationReversalService.AllocationPage after = service.listAllocations(
        query(f.holder.Id)
      );
      Assert.areEqual(
        1,
        after.items.size(),
        'the application stays listed as history'
      );
      Assert.areEqual(reversed.reversalId, after.items[0].reversalId);
      Assert.areEqual('WRONG_TARGET', after.items[0].reversalReason);
      Assert.areEqual(
        100,
        [
          SELECT AXF_BAT_NUM_Magnitude__c
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE Id = :f.fact.Id
        ]
        .AXF_BAT_NUM_Magnitude__c,
        'source fact preserved'
      );
    }
  }

  @IsTest
  static void reversingActualOnlyInventsNoForecastDebt() {
    System.runAs(byAlias('axf141g')) {
      Fixture f = fixture('actual', null);
      Id bornId = [
        SELECT AXF_RA_LKP_FinancialTransaction__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE Id = :f.allocationId
      ]
      .AXF_RA_LKP_FinancialTransaction__c;
      Test.startTest();
      ALT_CLS_ReconciliationReversalService.Result reversed = new ALT_CLS_ReconciliationReversalService()
        .reverse(input(f.allocationId, 1, 'DUPLICATE_LINK', null, 'actual'));
      Test.stopTest();
      Assert.isTrue(reversed.actualOnly);
      Assert.areEqual('ACTUAL_ONLY', reversed.planKind);
      Assert.areEqual(0, reversed.plannedAfter, 'no planned amount exists');
      Assert.areEqual(0, reversed.realizedAfter);
      Assert.areEqual(
        0,
        reversed.residualAfter,
        'no forecast debt is invented'
      );
      Assert.areEqual('NONE', reversed.stateAfter);
      Assert.areEqual(100, reversed.sourceResidualAfter);
      AXF_OBJ_FinancialTransaction__c born = [
        SELECT
          AXF_FTX_PKL_PlanKind__c,
          AXF_FTX_PKL_Status__c,
          AXF_FTX_NUM_Magnitude__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id = :bornId
      ];
      Assert.areEqual(
        'ACTUAL_ONLY',
        born.AXF_FTX_PKL_PlanKind__c,
        'role immutable'
      );
      Assert.areEqual(
        60,
        born.AXF_FTX_NUM_Magnitude__c,
        'magnitude preserved as history'
      );
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_FinancialTransaction__c
          WHERE AXF_FTX_PKL_PlanKind__c = 'PLANNED'
        ],
        'reversal creates no PLANNED transaction'
      );
    }
  }

  @IsTest
  static void guardsFailClosedAndPersistNothing() {
    Fixture f;
    System.runAs(byAlias('axf141g')) {
      f = fixture('guards', null);
    }
    Test.startTest();
    System.runAs(byAlias('axf141n')) {
      Assert.areEqual(
        'UNAVAILABLE',
        failure(input(f.allocationId, 1, 'OTHER', null, 'n')),
        'capability missing'
      );
      Assert.isFalse(
        AXF_CLS_CTRL_ReconciliationReversal.getContext(null).canReverse
      );
    }
    System.runAs(byAlias('axf141p')) {
      Assert.areEqual(
        'UNAVAILABLE',
        failure(input(f.allocationId, 1, 'OTHER', null, 'p')),
        'foreign holder is indistinguishable from missing'
      );
      try {
        new ALT_CLS_ReconciliationReversalService()
          .listAllocations(query(f.holder.Id));
        Assert.fail('foreign holder');
      } catch (ALT_CLS_ReconciliationReversalService.ReversalException expected) {
        Assert.areEqual('UNAVAILABLE', expected.getMessage());
      }
    }
    System.runAs(byAlias('axf141g')) {
      Assert.areEqual(
        'INVALID_REASON',
        failure(input(f.allocationId, 1, null, null, 'g1'))
      );
      Assert.areEqual(
        'INVALID_REASON',
        failure(input(f.allocationId, 1, 'BECAUSE', null, 'g2'))
      );
      Assert.areEqual(
        'INVALID',
        failure(input(f.allocationId, 1, 'OTHER', 'x'.repeat(256), 'g3'))
      );
      ALT_CLS_ReconciliationReversalService.Input noKey = input(
        f.allocationId,
        1,
        'OTHER',
        null,
        'g4'
      );
      noKey.operationKey = null;
      Assert.areEqual('INVALID', failure(noKey));
      Assert.areEqual(
        'CONFLICT',
        failure(input(f.allocationId, 7, 'OTHER', null, 'stale'))
      );
      AXF_CLS_CTRL_ReconciliationReversal.Context context = AXF_CLS_CTRL_ReconciliationReversal.getContext(
        null
      );
      Assert.isTrue(context.canReverse);
      Assert.areEqual(
        ALT_CLS_ReconciliationReversalService.REASONS,
        context.reasons
      );
      try {
        AXF_CLS_CTRL_ReconciliationReversal.reverse('{"nope":1}');
        Assert.fail('strict shape');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', expected.getMessage());
      }
      try {
        AXF_CLS_CTRL_ReconciliationReversal.listAllocations(
          JSON.serialize(query(null))
        );
        Assert.fail('account required');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID', expected.getMessage());
      }
      Assert.isNull(
        AXF_CLS_CTRL_ReconciliationReversal.priorReversal(f.allocationId),
        'nothing reversed'
      );
      ALT_CLS_ReconciliationReversalService.Result result = AXF_CLS_CTRL_ReconciliationReversal.reverse(
        JSON.serialize(
          input(f.allocationId, 1, 'SOURCE_CHANGED', 'ctrl', 'ctrl')
        )
      );
      Assert.isNotNull(result.reversalId);
      // A compensation is never a reversal target.
      Assert.areEqual(
        'INVALID_TARGET',
        failure(input(result.reversalId, 2, 'OTHER', null, 'rr'))
      );
    }
    Test.stopTest();
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM AXF_OBJ_ReconciliationAllocation__c],
      'only the application and its single compensation exist'
    );
  }
}
