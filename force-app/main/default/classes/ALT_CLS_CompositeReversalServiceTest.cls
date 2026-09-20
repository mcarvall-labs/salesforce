/**
 * @description AXF-142: reversao composta orquestra N chamadas ao primitivo de AXF-141 sob um
 * savepoint proprio, CONFIRMED->REVERSING->REVERSED, com rollback total de qualquer falha no meio
 * (nenhuma allocation fica parcialmente revertida) e replay idempotente por operationKey.
 */
@IsTest(isParallel=false)
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class ALT_CLS_CompositeReversalServiceTest {
  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    List<User> users = new List<User>();
    for (String alias : new List<String>{ 'axf142g', 'axf142p', 'axf142n' }) {
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
    public AXF_OBJ_BankAccountTransaction__c fact;
    public List<AXF_OBJ_FinancialTransaction__c> targets = new List<AXF_OBJ_FinancialTransaction__c>();
    public ALT_CLS_ReconciliationService.ConfirmResult confirmed;
  }

  /** Holder, one POSTED fact of 100 and a composite RCN of two APPLICATION lines (60 + 40). */
  private static Fixture fixture(String key) {
    Fixture f = new Fixture();
    f.holder = new Account(
      Name = 'Holder 142 ' + key,
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert f.holder;
    AXF_OBJ_BankAccount__c bank = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = f.holder.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL'
    );
    insert bank;
    f.fact = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bank.Id,
      AXF_BAT_NUM_Magnitude__c = 100,
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_DAT_Date__c = Date.today(),
      AXF_BAT_TXT_Description__c = 'Fact ' + key,
      AXF_BAT_EXI_SourceKey__c = 'axf142-' + key,
      AXF_BAT_PKL_Source__c = 'CSV',
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_NUM_Version__c = 0
    );
    insert f.fact;
    Integer sequence = 0;
    for (Decimal amount : new List<Decimal>{ 60, 40 }) {
      sequence++;
      f.targets.add(
        new AXF_OBJ_FinancialTransaction__c(
          AXF_FTX_LKP_Account__c = f.holder.Id,
          AXF_FTX_NUM_Magnitude__c = amount,
          AXF_FTX_PKL_Direction__c = 'DEBIT',
          AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
          AXF_FTX_DAT_PurchaseDate__c = Date.today(),
          AXF_FTX_DAT_DueDate__c = Date.today().addDays(sequence),
          AXF_FTX_TXT_Description__c = 'Target ' + key + ' ' + sequence,
          AXF_FTX_PKL_PlanKind__c = 'PLANNED',
          AXF_FTX_PKL_Status__c = 'PLANNED',
          AXF_FTX_NUM_Version__c = 0,
          AXF_FTX_EXI_ClientRequestId__c = 'ftx-142-' + key + '-' + sequence
        )
      );
    }
    insert f.targets;
    ALT_CLS_ReconciliationService.LineInput line1 = new ALT_CLS_ReconciliationService.LineInput();
    line1.factKind = 'BANK';
    line1.factId = f.fact.Id;
    line1.targetId = f.targets[0].Id;
    line1.amount = 60;
    ALT_CLS_ReconciliationService.LineInput line2 = new ALT_CLS_ReconciliationService.LineInput();
    line2.factKind = 'BANK';
    line2.factId = f.fact.Id;
    line2.targetId = f.targets[1].Id;
    line2.amount = 40;
    ALT_CLS_ReconciliationService.ConfirmInput confirm = new ALT_CLS_ReconciliationService.ConfirmInput();
    confirm.lines = new List<ALT_CLS_ReconciliationService.LineInput>{
      line1,
      line2
    };
    confirm.expectedVersion = 0;
    confirm.correlationId = correlation(key);
    confirm.idempotencyKey = 'axf142-confirm-' + key;
    f.confirmed = new ALT_CLS_ReconciliationService().confirm(confirm);
    return f;
  }

  /** Lighter single-line RCN: enough to prove the redistribution surface without spending most of
   * the 100-query synchronous budget on a 2-line composite reversal in the same governor context. */
  private static Fixture singleLineFixture(String key) {
    Fixture f = new Fixture();
    f.holder = new Account(
      Name = 'Holder 142 ' + key,
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert f.holder;
    AXF_OBJ_BankAccount__c bank = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = f.holder.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL'
    );
    insert bank;
    f.fact = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bank.Id,
      AXF_BAT_NUM_Magnitude__c = 100,
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_DAT_Date__c = Date.today(),
      AXF_BAT_TXT_Description__c = 'Fact ' + key,
      AXF_BAT_EXI_SourceKey__c = 'axf142-' + key,
      AXF_BAT_PKL_Source__c = 'CSV',
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_NUM_Version__c = 0
    );
    insert f.fact;
    f.targets.add(
      new AXF_OBJ_FinancialTransaction__c(
        AXF_FTX_LKP_Account__c = f.holder.Id,
        AXF_FTX_NUM_Magnitude__c = 100,
        AXF_FTX_PKL_Direction__c = 'DEBIT',
        AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_FTX_DAT_PurchaseDate__c = Date.today(),
        AXF_FTX_DAT_DueDate__c = Date.today().addDays(1),
        AXF_FTX_TXT_Description__c = 'Target ' + key,
        AXF_FTX_PKL_PlanKind__c = 'PLANNED',
        AXF_FTX_PKL_Status__c = 'PLANNED',
        AXF_FTX_NUM_Version__c = 0,
        AXF_FTX_EXI_ClientRequestId__c = 'ftx-142-' + key
      )
    );
    insert f.targets;
    ALT_CLS_ReconciliationService.LineInput line = new ALT_CLS_ReconciliationService.LineInput();
    line.factKind = 'BANK';
    line.factId = f.fact.Id;
    line.targetId = f.targets[0].Id;
    line.amount = 100;
    ALT_CLS_ReconciliationService.ConfirmInput confirm = new ALT_CLS_ReconciliationService.ConfirmInput();
    confirm.lines = new List<ALT_CLS_ReconciliationService.LineInput>{ line };
    confirm.expectedVersion = 0;
    confirm.correlationId = correlation(key);
    confirm.idempotencyKey = 'axf142-confirm-' + key;
    f.confirmed = new ALT_CLS_ReconciliationService().confirm(confirm);
    return f;
  }

  private static String correlation(String seed) {
    String body = String.valueOf(Math.abs(Crypto.getRandomInteger()));
    String hex = EncodingUtil.convertToHex(
        Crypto.generateDigest('SHA-256', Blob.valueOf(seed + body))
      )
      .toLowerCase();
    return hex.substring(0, 8) +
      '-' +
      hex.substring(8, 12) +
      '-4' +
      hex.substring(13, 16) +
      '-8' +
      hex.substring(17, 20) +
      '-' +
      hex.substring(20, 32);
  }

  private static ALT_CLS_CompositeReversalService.Input input(
    Id reconciliationId,
    Decimal expectedVersion,
    String key
  ) {
    ALT_CLS_CompositeReversalService.Input i = new ALT_CLS_CompositeReversalService.Input();
    i.reconciliationId = reconciliationId;
    i.expectedVersion = expectedVersion;
    i.reasonCode = 'WRONG_TARGET';
    i.reasonNote = 'composite correction';
    i.operationKey = 'axf142-composite-' + key;
    return i;
  }

  private static String failure(ALT_CLS_CompositeReversalService.Input i) {
    try {
      new ALT_CLS_CompositeReversalService().reverse(i);
      return null;
    } catch (Exception expected) {
      // requireAccess() (capability-only) throws AXF-141's ReversalException before the
      // orchestrator's own Savepoint even opens; everything else is CompositeReversalException.
      return expected.getMessage();
    }
  }

  @IsTest
  static void compositeReversalMovesAllAllocationsAndTheRcnAtomically() {
    System.runAs(byAlias('axf142g')) {
      Fixture f = fixture('happy');
      ALT_CLS_CompositeReversalService.RcnView before = new ALT_CLS_CompositeReversalService()
        .listAllocations(f.confirmed.reconciliationId);

      Test.startTest();
      ALT_CLS_CompositeReversalService.Result result = new ALT_CLS_CompositeReversalService()
        .reverse(
          input(f.confirmed.reconciliationId, f.confirmed.version, 'happy')
        );
      ALT_CLS_CompositeReversalService.Result replayed = new ALT_CLS_CompositeReversalService()
        .reverse(input(f.confirmed.reconciliationId, result.version, 'happy'));
      Test.stopTest();

      Assert.areEqual(2, before.allocations.size());
      Assert.isFalse(result.replayed);
      Assert.areEqual('REVERSED', result.state);
      Assert.areEqual(2, result.lines.size());
      for (ALT_CLS_CompositeReversalService.LineResult line : result.lines) {
        Assert.isNotNull(line.reversalId);
        Assert.isFalse(line.replayed);
      }
      Assert.isTrue(
        replayed.replayed,
        'same operationKey replays without duplicating'
      );
      Assert.areEqual('REVERSED', replayed.state);
      Assert.areEqual(result.lines[0].reversalId, replayed.lines[0].reversalId);
      Assert.areEqual(result.lines[1].reversalId, replayed.lines[1].reversalId);
      Assert.areEqual(
        'REVERSED',
        [
          SELECT AXF_RCN_PKL_State__c
          FROM AXF_OBJ_Reconciliation__c
          WHERE Id = :f.confirmed.reconciliationId
        ]
        .AXF_RCN_PKL_State__c
      );
      Set<Id> originalIds = new Set<Id>();
      for (ALT_CLS_CompositeReversalService.LineResult line : result.lines) {
        originalIds.add(line.allocationId);
      }
      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM AXF_OBJ_ReconciliationAllocation__c
          WHERE
            AXF_RA_PKL_Kind__c = 'REVERSAL'
            AND AXF_RA_LKP_OriginalAllocation__c IN :originalIds
        ],
        // AXF-141's own compensation row does not carry AXF_RA_LKP_Reconciliation__c (RA_FIELDS
        // never selects it), so provenance is proven via AXF_RA_LKP_OriginalAllocation__c instead.
        'both applications got exactly one compensation each; the replay added none'
      );
    }
  }

  @IsTest
  static void aFailureMidReversalRollsBackEveryLineAndKeepsTheRcnConfirmed() {
    System.runAs(byAlias('axf142g')) {
      Fixture f = fixture('partial');
      Id firstAllocationId = [
        SELECT Id
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE
          AXF_RA_LKP_Reconciliation__c = :f.confirmed.reconciliationId
          AND AXF_RA_PKL_Kind__c = 'APPLICATION'
        ORDER BY Id
        LIMIT 1
      ]
      .Id;
      Test.startTest();
      // Reverse the first allocation directly (outside the composite command) so the composite
      // reversal collides with it under a different operationKey (ALREADY_REVERSED).
      ALT_CLS_ReconciliationReversalService.Input direct = new ALT_CLS_ReconciliationReversalService.Input();
      direct.allocationId = firstAllocationId;
      direct.expectedVersion = [
        SELECT AXF_FTX_NUM_Version__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id = :f.targets[0].Id
      ]
      .AXF_FTX_NUM_Version__c;
      direct.reasonCode = 'OTHER';
      direct.operationKey = 'axf142-direct-partial';
      new ALT_CLS_ReconciliationReversalService().reverse(direct);

      String code = failure(
        input(f.confirmed.reconciliationId, f.confirmed.version, 'partial')
      );
      Test.stopTest();

      Assert.areEqual('ALREADY_REVERSED', code);
      Assert.areEqual(
        'CONFIRMED',
        [
          SELECT AXF_RCN_PKL_State__c
          FROM AXF_OBJ_Reconciliation__c
          WHERE Id = :f.confirmed.reconciliationId
        ]
        .AXF_RCN_PKL_State__c,
        'the RCN rolls back to CONFIRMED: no partial compensation survives'
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_ReconciliationAllocation__c
          WHERE
            AXF_RA_PKL_Kind__c = 'REVERSAL'
            AND AXF_RA_LKP_OriginalAllocation__c = :firstAllocationId
        ],
        'only the single direct reversal exists; the composite command added none'
      );
    }
  }

  @IsTest
  static void aFailureOnALaterLineRollsBackEveryEarlierLineOfTheSameOperation() {
    System.runAs(byAlias('axf142g')) {
      Fixture f = fixture('partial2');
      // applications() (and this query) both order by Id: the collision below is arranged on the
      // allocation the composite loop processes SECOND, so a rollback that only undid the second
      // line's own DML would still leave the FIRST line's compensation behind.
      List<AXF_OBJ_ReconciliationAllocation__c> apps = [
        SELECT Id, AXF_RA_LKP_FinancialTransaction__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE
          AXF_RA_LKP_Reconciliation__c = :f.confirmed.reconciliationId
          AND AXF_RA_PKL_Kind__c = 'APPLICATION'
        ORDER BY Id
      ];
      Id firstProcessedAllocationId = apps[0].Id;
      Id secondProcessedAllocationId = apps[1].Id;
      Test.startTest();
      // Reverse the SECOND-processed allocation directly (outside the composite command) so the
      // composite reversal collides with it under a different operationKey (ALREADY_REVERSED)
      // only after it has already written the first line's compensation in this same operation.
      ALT_CLS_ReconciliationReversalService.Input direct = new ALT_CLS_ReconciliationReversalService.Input();
      direct.allocationId = secondProcessedAllocationId;
      direct.expectedVersion = [
        SELECT AXF_FTX_NUM_Version__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id = :apps[1].AXF_RA_LKP_FinancialTransaction__c
      ]
      .AXF_FTX_NUM_Version__c;
      direct.reasonCode = 'OTHER';
      direct.operationKey = 'axf142-direct-partial2';
      new ALT_CLS_ReconciliationReversalService().reverse(direct);

      String code = failure(
        input(f.confirmed.reconciliationId, f.confirmed.version, 'partial2')
      );
      Test.stopTest();

      Assert.areEqual('ALREADY_REVERSED', code);
      Assert.areEqual(
        'CONFIRMED',
        [
          SELECT AXF_RCN_PKL_State__c
          FROM AXF_OBJ_Reconciliation__c
          WHERE Id = :f.confirmed.reconciliationId
        ]
        .AXF_RCN_PKL_State__c,
        'the RCN rolls back to CONFIRMED even though the failure happened on the later line'
      );
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_ReconciliationAllocation__c
          WHERE
            AXF_RA_PKL_Kind__c = 'REVERSAL'
            AND AXF_RA_LKP_OriginalAllocation__c = :firstProcessedAllocationId
        ],
        'the first line, written earlier in this same operation, is rolled back too'
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_ReconciliationAllocation__c
          WHERE
            AXF_RA_PKL_Kind__c = 'REVERSAL'
            AND AXF_RA_LKP_OriginalAllocation__c = :secondProcessedAllocationId
        ],
        'only the single direct (out-of-band) reversal of the second line survives'
      );
    }
  }

  @IsTest
  static void guardsFailClosedAndPersistNothing() {
    Fixture f;
    System.runAs(byAlias('axf142g')) {
      f = fixture('guards');
    }
    Test.startTest();
    System.runAs(byAlias('axf142n')) {
      Assert.areEqual(
        'UNAVAILABLE',
        failure(input(f.confirmed.reconciliationId, f.confirmed.version, 'n'))
      );
      AXF_CLS_CTRL_CompositeReversal.Context denied = AXF_CLS_CTRL_CompositeReversal.getContext(
        null
      );
      Assert.isFalse(denied.canReverse);
      Assert.isFalse(denied.canRedistribute);
      Assert.isTrue(denied.holders.isEmpty());
      try {
        AXF_CLS_CTRL_CompositeReversal.reverseComposite(
          JSON.serialize(
            input(f.confirmed.reconciliationId, f.confirmed.version, 'ctrln')
          )
        );
        Assert.fail('capability missing');
      } catch (AuraHandledException expected) {
        Assert.areEqual('UNAVAILABLE', expected.getMessage());
      }
      try {
        AXF_CLS_CTRL_CompositeReversal.redistribute(
          JSON.serialize(new ALT_CLS_ReconciliationService.RedistributeInput())
        );
        Assert.fail('capability missing');
      } catch (AuraHandledException expected) {
        Assert.areEqual('UNAVAILABLE', expected.getMessage());
      }
    }
    System.runAs(byAlias('axf142p')) {
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(input(f.confirmed.reconciliationId, f.confirmed.version, 'p')),
        'foreign holder is indistinguishable from missing'
      );
    }
    System.runAs(byAlias('axf142g')) {
      Assert.areEqual(
        'CONFLICT',
        failure(input(f.confirmed.reconciliationId, 999, 'stale')),
        'stale version rejects the whole command'
      );
      ALT_CLS_CompositeReversalService.Input badReason = input(
        f.confirmed.reconciliationId,
        f.confirmed.version,
        'reason'
      );
      badReason.reasonCode = 'BECAUSE';
      Assert.areEqual('INVALID', failure(badReason));
    }
    Test.stopTest();
    Assert.areEqual(
      'CONFIRMED',
      [
        SELECT AXF_RCN_PKL_State__c
        FROM AXF_OBJ_Reconciliation__c
        WHERE Id = :f.confirmed.reconciliationId
      ]
      .AXF_RCN_PKL_State__c
    );
  }

  @IsTest
  static void listReconciliationsAndControllerSurfaceCompositeReversal() {
    System.runAs(byAlias('axf142g')) {
      Fixture f = fixture('ctrl');
      Test.startTest();
      List<ALT_CLS_CompositeReversalService.RcnSummary> summaries = AXF_CLS_CTRL_CompositeReversal.listReconciliations(
        f.holder.Id
      );
      Boolean found = false;
      for (ALT_CLS_CompositeReversalService.RcnSummary summary : summaries) {
        if (summary.reconciliationId == f.confirmed.reconciliationId) {
          found = true;
          Assert.areEqual(2, summary.allocationCount);
        }
      }
      Assert.isTrue(found);

      AXF_CLS_CTRL_CompositeReversal.Context context = AXF_CLS_CTRL_CompositeReversal.getContext(
        null
      );
      Assert.isTrue(context.canReverse);
      Assert.isTrue(context.canRedistribute);

      ALT_CLS_CompositeReversalService.RcnView view = AXF_CLS_CTRL_CompositeReversal.listAllocations(
        f.confirmed.reconciliationId
      );
      Assert.areEqual(2, view.allocations.size());

      ALT_CLS_CompositeReversalService.Result reversed = AXF_CLS_CTRL_CompositeReversal.reverseComposite(
        JSON.serialize(
          input(f.confirmed.reconciliationId, f.confirmed.version, 'ctrl')
        )
      );
      Assert.areEqual('REVERSED', reversed.state);

      try {
        AXF_CLS_CTRL_CompositeReversal.reverseComposite('{"nope":1}');
        Assert.fail('strict shape');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', expected.getMessage());
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void controllerSurfacesRedistributionAfterAReversal() {
    System.runAs(byAlias('axf142g')) {
      Fixture f = singleLineFixture('ctrlredist');
      Id firstOriginal = [
        SELECT Id
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE
          AXF_RA_LKP_Reconciliation__c = :f.confirmed.reconciliationId
          AND AXF_RA_PKL_Kind__c = 'APPLICATION'
        ORDER BY Id
        LIMIT 1
      ]
      .Id;
      new ALT_CLS_CompositeReversalService()
        .reverse(
          input(f.confirmed.reconciliationId, f.confirmed.version, 'ctrlredist')
        );
      Test.startTest();
      ALT_CLS_ReconciliationService.RedistributeInput redistribute = new ALT_CLS_ReconciliationService.RedistributeInput();
      ALT_CLS_ReconciliationService.LineInput redistLine = new ALT_CLS_ReconciliationService.LineInput();
      redistLine.factKind = 'BANK';
      redistLine.factId = f.fact.Id;
      redistLine.targetId = f.targets[0].Id;
      redistLine.amount = 100;
      redistribute.originalAllocationId = firstOriginal;
      redistribute.lines = new List<ALT_CLS_ReconciliationService.LineInput>{
        redistLine
      };
      redistribute.correlationId = correlation('ctrl-redist');
      redistribute.idempotencyKey = 'axf142-ctrl-redist';
      redistribute.reasonCode = 'OTHER';
      ALT_CLS_ReconciliationService.ConfirmResult redistributed = AXF_CLS_CTRL_CompositeReversal.redistribute(
        JSON.serialize(redistribute)
      );
      Test.stopTest();

      Assert.areEqual(
        ALT_CLS_ReconciliationService.STATE_CONFIRMED,
        redistributed.state
      );
    }
  }
}
