/** @description Conservation, replay, immutable history and FX recovery contracts for AXF-25. */
@IsTest
private class ALT_CLS_RealizationServiceTest {
  private static User actor() {
    return [SELECT Id FROM User WHERE Alias = 'axf25' LIMIT 1];
  }
  @TestSetup
  static void setup() {
    User actor = new User(
      Alias = 'axf25',
      Email = 'axf25@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Realization Tester',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
      .Id,
      Username = 'axf25.' + System.now().getTime() + '@example.invalid'
    );
    insert actor;
    User peer = actor.clone(false, false, false, false);
    peer.Alias = 'axf25b';
    peer.Username = 'axf25b.' + System.now().getTime() + '@example.invalid';
    insert peer;
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet permission : [
      SELECT Id
      FROM PermissionSet
      WHERE
        Name IN (
          'AXF_PS_Realization',
          'AXF_PS_FinancialEntry',
          'AXF_PS_GestorFinanceiro'
        )
    ]) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = actor.Id,
          PermissionSetId = permission.Id
        )
      );
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = peer.Id,
          PermissionSetId = permission.Id
        )
      );
    }
    insert assignments;
    PermissionSet capability = new PermissionSet(
      Name = 'AXF25TestCapability',
      Label = 'AXF25 test capability'
    );
    insert capability;
    insert new SetupEntityAccess(
      ParentId = capability.Id,
      SetupEntityId = [
        SELECT Id
        FROM CustomPermission
        WHERE DeveloperName = 'AXF_CanRealize'
      ]
      .Id
    );
    insert new PermissionSetAssignment(
      AssigneeId = actor.Id,
      PermissionSetId = capability.Id
    );
    insert new PermissionSetAssignment(
      AssigneeId = peer.Id,
      PermissionSetId = capability.Id
    );
    insert new AXF_ReportCurrencyPref__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      AXF_RCP_TXT_IsoCode__c = 'BRL'
    );
  }
  @IsTest
  static void snapshotPersistenceFailureRollsBackWholeRealization() {
    System.runAs(actor()) {
      AXF_OBJ_FinancialTransaction__c target = plan('USD');
      target.AXF_FTX_NUM_Magnitude__c = 9999999999999.0;
      update target;
      rate(999999, Date.today(), 'SELL');
      Test.startTest();
      try {
        new ALT_CLS_RealizationService()
          .apply(request(target.Id, 9999999999999.0, 0, 'overflow'));
        Assert.fail('Reporting amount exceeds snapshot precision');
      } catch (Exception expected) {
        Assert.isNotNull(expected);
      }
      Test.stopTest();
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_ReconciliationAllocation__c]
      );
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_FxApplicationSnapshot__c]
      );
      Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c]);
      Assert.areEqual(
        0,
        [
          SELECT AXF_FTX_NUM_Version__c
          FROM AXF_OBJ_FinancialTransaction__c
          WHERE Id = :target.Id
        ]
        .AXF_FTX_NUM_Version__c
      );
    }
  }
  @IsTest
  static void unassignedUserCannotInvokeRealization() {
    Test.startTest();
    Boolean denied = false;
    try {
      new ALT_CLS_RealizationService().apply(request(null, 1, 0, 'denied'));
    } catch (ALT_CLS_RealizationService.RealizationException expected) {
      denied = true;
      Assert.areEqual('UNAVAILABLE', expected.getMessage());
    }
    Test.stopTest();
    Assert.isTrue(denied);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AXF_OBJ_ReconciliationAllocation__c]
    );
  }
  @IsTest
  static void partialSharingCannotDiscloseIncompleteTotalsOrSourceLinks() {
    User peer = [SELECT Id FROM User WHERE Alias = 'axf25b' LIMIT 1];
    AXF_OBJ_FinancialTransaction__c target;
    Id effect;
    System.runAs(actor()) {
      target = plan('BRL');
      effect = new ALT_CLS_RealizationService()
        .apply(request(target.Id, 40, 0, 'private'));
      insert new AccountShare(
        AccountId = target.AXF_FTX_LKP_Account__c,
        UserOrGroupId = peer.Id,
        AccountAccessLevel = 'Read',
        OpportunityAccessLevel = 'None',
        CaseAccessLevel = 'None'
      );
      insert new AXF_OBJ_FinancialTransaction__Share(
        ParentId = target.Id,
        UserOrGroupId = peer.Id,
        AccessLevel = 'Edit'
      );
    }
    Test.startTest();
    System.runAs(peer) {
      try {
        AXF_CLS_CTRL_Realization.read(target.Id);
        Assert.fail('A hidden allocation cannot yield a false zero');
      } catch (AuraHandledException expected) {
        Assert.areEqual('UNAVAILABLE', expected.getMessage());
      }
    }
    System.runAs(actor()) {
      insert new AXF_OBJ_ReconciliationAllocation__Share(
        ParentId = effect,
        UserOrGroupId = peer.Id,
        AccessLevel = 'Read'
      );
    }
    System.runAs(peer) {
      try {
        AXF_CLS_CTRL_Realization.read(target.Id);
        Assert.fail('An allocation link does not authorize its private fact');
      } catch (AuraHandledException expected) {
        Assert.areEqual('UNAVAILABLE', expected.getMessage());
      }
    }
    Test.stopTest();
  }
  @IsTest
  static void creditApplicationsUseTheirDatesAndReversalKeepsOriginalFx() {
    System.runAs(actor()) {
      AXF_OBJ_FinancialTransaction__c target = plan('USD');
      target.AXF_FTX_PKL_Direction__c = 'CREDIT';
      update target;
      rate(5, Date.today().addDays(-1), 'BUY');
      rate(6, Date.today(), 'BUY');
      ALT_CLS_RealizationService service = new ALT_CLS_RealizationService();
      ALT_CLS_RealizationService.Input first = request(
        target.Id,
        40,
        0,
        'credit-first'
      );
      first.recognitionDate = Date.today().addDays(-1);
      Id firstId = service.apply(first);
      Test.startTest();
      service.apply(request(target.Id, 60, 1, 'credit-second'));
      Assert.areEqual(
        560,
        service.read(target.Id).reportingAmount,
        'Each application uses its own amount and date'
      );
      Id reverseId = service.reverse(firstId, 2, 'credit-reverse');
      Test.stopTest();
      Assert.areEqual(
        360,
        service.read(target.Id).reportingAmount,
        'Reversal removes the historical 200, not a current-rate value'
      );
      Assert.areEqual(
        2,
        [SELECT COUNT() FROM AXF_OBJ_FxApplicationSnapshot__c]
      );
      Assert.areEqual(
        [
          SELECT AXF_RA_LKP_FxSnapshot__c
          FROM AXF_OBJ_ReconciliationAllocation__c
          WHERE Id = :firstId
        ]
        .AXF_RA_LKP_FxSnapshot__c,
        [
          SELECT AXF_RA_LKP_FxSnapshot__c
          FROM AXF_OBJ_ReconciliationAllocation__c
          WHERE Id = :reverseId
        ]
        .AXF_RA_LKP_FxSnapshot__c
      );
    }
  }
  private static AXF_OBJ_FinancialTransaction__c plan(String iso) {
    Account holder = new Account(
      Name = 'Realization holder',
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert holder;
    AXF_OBJ_FinancialTransaction__c result = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = holder.Id,
      AXF_FTX_NUM_Magnitude__c = 100,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = iso,
      AXF_FTX_DAT_PurchaseDate__c = Date.today(),
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_NUM_Version__c = 0,
      AXF_FTX_EXI_ClientRequestId__c = String.valueOf(holder.Id) + '-plan'
    );
    insert result;
    return result;
  }
  private static ALT_CLS_RealizationService.Input request(
    Id targetId,
    Decimal amount,
    Decimal expected,
    String key
  ) {
    ALT_CLS_RealizationService.Input result = new ALT_CLS_RealizationService.Input();
    result.targetId = targetId;
    result.sourceKind = 'CASH';
    result.amount = amount;
    result.recognitionDate = Date.today();
    result.targetVersion = expected;
    result.operationKey = key;
    return result;
  }
  private static void rate(Decimal amount, Date day, String side) {
    insert new AXF_OBJ_ExchangeRate__c(
      AXF_EXR_TXT_BaseCurrency__c = 'USD',
      AXF_EXR_TXT_QuoteCurrency__c = 'BRL',
      AXF_EXR_NUM_Rate__c = amount,
      AXF_EXR_PKL_Side__c = side,
      AXF_EXR_TXT_Provider__c = 'BCB_PTAX',
      AXF_EXR_DT_EffectiveDateTime__c = Datetime.newInstance(
        day,
        Time.newInstance(12, 0, 0, 0)
      ),
      AXF_EXR_EXI_RateKey__c = 'test-' +
        String.valueOf(day) +
        '-' +
        side +
        '-' +
        amount
    );
  }
  @IsTest
  static void partialThenTotalPreservesPlan() {
    System.runAs(actor()) {
      AXF_OBJ_FinancialTransaction__c target = plan('BRL');
      ALT_CLS_RealizationService service = new ALT_CLS_RealizationService();
      Test.startTest();
      AXF_CLS_CTRL_Realization.Applied first = AXF_CLS_CTRL_Realization.apply(
        JSON.serialize(request(target.Id, 40, 0, 'first'))
      );
      ALT_CLS_RealizationService.View partial = service.read(target.Id);
      Assert.areEqual(60, partial.residual);
      Assert.areEqual(40, partial.realized);
      Assert.areEqual('PARTIAL', partial.state);
      service.apply(request(target.Id, 60, 1, 'second'));
      ALT_CLS_RealizationService.View total = service.read(target.Id);
      Test.stopTest();
      Assert.areEqual(100, total.planned);
      Assert.areEqual(100, total.realized);
      Assert.areEqual(0, total.residual);
      Assert.areEqual('REALIZED', total.state);
      Assert.areEqual(
        100,
        [
          SELECT AXF_FTX_NUM_Magnitude__c
          FROM AXF_OBJ_FinancialTransaction__c
          WHERE Id = :target.Id
        ]
        .AXF_FTX_NUM_Magnitude__c
      );
    }
  }
  @IsTest
  static void replayAndStaleVersionHaveNoExtraEffect() {
    System.runAs(actor()) {
      Id targetId = plan('BRL').Id;
      ALT_CLS_RealizationService service = new ALT_CLS_RealizationService();
      ALT_CLS_RealizationService.Input input = request(
        targetId,
        40,
        0,
        'replay'
      );
      Test.startTest();
      Id first = service.apply(input);
      Assert.areEqual(first, service.apply(input));
      input.amount = 50;
      try {
        service.apply(input);
        Assert.fail('Changed payload must conflict');
      } catch (ALT_CLS_RealizationService.RealizationException expected) {
        Assert.areEqual('CONFLICT', expected.getMessage());
      }
      try {
        service.apply(request(targetId, 40, 0, 'stale'));
        Assert.fail('Stale writer must conflict');
      } catch (ALT_CLS_RealizationService.RealizationException expected) {
        Assert.areEqual('CONFLICT', expected.getMessage());
      }
      Test.stopTest();
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM AXF_OBJ_ReconciliationAllocation__c]
      );
      Assert.areEqual(2, [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c]);
    }
  }
  @IsTest
  static void excessRollsBackCreatedCashFact() {
    System.runAs(actor()) {
      Id targetId = plan('BRL').Id;
      Test.startTest();
      try {
        new ALT_CLS_RealizationService()
          .apply(request(targetId, 101, 0, 'excess'));
        Assert.fail('No over-allocation');
      } catch (ALT_CLS_RealizationService.RealizationException expected) {
        Assert.areEqual('UNAVAILABLE_AMOUNT', expected.getMessage());
      }
      Test.stopTest();
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_ReconciliationAllocation__c]
      );
      Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c]);
    }
  }
  @IsTest
  static void reversalPreservesHistoryAndReplays() {
    System.runAs(actor()) {
      Id targetId = plan('BRL').Id;
      ALT_CLS_RealizationService service = new ALT_CLS_RealizationService();
      Test.startTest();
      Id original = service.apply(request(targetId, 40, 0, 'original'));
      Id reversal = AXF_CLS_CTRL_Realization.reverse(original, 1, 'reverse');
      Assert.areEqual(reversal, service.reverse(original, 1, 'reverse'));
      try {
        service.reverse(original, 2, 'twice');
        Assert.fail('No second compensation');
      } catch (ALT_CLS_RealizationService.RealizationException expected) {
        Assert.areEqual('CONFLICT', expected.getMessage());
      }
      ALT_CLS_RealizationService.View state = service.read(targetId);
      Test.stopTest();
      Assert.areEqual(0, state.realized);
      Assert.areEqual(100, state.residual);
      Assert.areEqual(2, state.allocations.size());
    }
  }
  @IsTest
  static void missingFxRecoversOnlyRecognitionAndFreezesRate() {
    System.runAs(actor()) {
      Id targetId = plan('USD').Id;
      ALT_CLS_RealizationService service = new ALT_CLS_RealizationService();
      rate(99, Date.today().addDays(1), 'SELL');
      rate(88, Date.today(), 'BUY');
      Test.startTest();
      Id original = service.apply(request(targetId, 40, 0, 'fx'));
      ALT_CLS_RealizationService.View pending = service.read(targetId);
      Assert.isTrue(pending.pendingFx);
      Assert.isNull(pending.reportingAmount);
      Assert.areEqual(40, pending.realized);
      rate(5, Date.today(), 'SELL');
      AXF_CLS_CTRL_Realization.retryFx(original);
      service.retryFx(original);
      ALT_CLS_RealizationService.View ready = service.read(targetId);
      Test.stopTest();
      Assert.isFalse(ready.pendingFx);
      Assert.areEqual(200, ready.reportingAmount);
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM AXF_OBJ_ReconciliationAllocation__c]
      );
      AXF_OBJ_FxApplicationSnapshot__c frozen = [
        SELECT AXF_FXS_NUM_OriginalAmount__c, AXF_FXS_NUM_ReportingAmount__c
        FROM AXF_OBJ_FxApplicationSnapshot__c
      ];
      Assert.areEqual(40, frozen.AXF_FXS_NUM_OriginalAmount__c);
      Assert.areEqual(200, frozen.AXF_FXS_NUM_ReportingAmount__c);
    }
  }
  @IsTest
  static void actualOnlyUsesDistinctCashRoleWithoutProjection() {
    System.runAs(actor()) {
      AXF_OBJ_FinancialTransaction__c holderPlan = plan('BRL');
      ALT_CLS_RealizationService.Input input = request(
        null,
        40,
        null,
        'actual'
      );
      input.accountId = holderPlan.AXF_FTX_LKP_Account__c;
      input.currencyIso = 'BRL';
      input.direction = 'DEBIT';
      Test.startTest();
      Id id = new ALT_CLS_RealizationService().apply(input);
      AXF_OBJ_ReconciliationAllocation__c allocation = [
        SELECT
          AXF_RA_LKP_FinancialTransaction__c,
          AXF_RA_LKP_ManualTransaction__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE Id = :id
      ];
      ALT_CLS_RealizationService.View result = new ALT_CLS_RealizationService()
        .read(allocation.AXF_RA_LKP_FinancialTransaction__c);
      Test.stopTest();
      Assert.areNotEqual(
        allocation.AXF_RA_LKP_FinancialTransaction__c,
        allocation.AXF_RA_LKP_ManualTransaction__c
      );
      Assert.areEqual(0, result.planned);
      Assert.areEqual(0, result.residual);
      Assert.areEqual(40, result.realized);
    }
  }
  @IsTest
  static void directHistoryEditsAndRoleForgeryFail() {
    System.runAs(actor()) {
      AXF_OBJ_FinancialTransaction__c target = plan('BRL');
      Id id = new ALT_CLS_RealizationService()
        .apply(request(target.Id, 40, 0, 'immutable'));
      Test.startTest();
      target.AXF_FTX_NUM_Magnitude__c = 200;
      Assert.isFalse(Database.update(target, false).isSuccess());
      Assert.isFalse(
        Database.delete(new AXF_OBJ_ReconciliationAllocation__c(Id = id), false)
          .isSuccess()
      );
      Assert.isFalse(
        Database.update(
            new AXF_OBJ_ReconciliationAllocation__c(
              Id = id,
              AXF_RA_NUM_Magnitude__c = 20
            ),
            false
          )
          .isSuccess()
      );
      target.AXF_FTX_PKL_PlanKind__c = 'CASH_FACT';
      Assert.isFalse(Database.update(target, false).isSuccess());
      Test.stopTest();
    }
  }
  @IsTest
  static void invalidControllerRequestsStaySanitized() {
    System.runAs(actor()) {
      Test.startTest();
      try {
        AXF_CLS_CTRL_Realization.apply('{');
        Assert.fail();
      } catch (AuraHandledException expected) {
        Assert.areEqual('UNAVAILABLE', expected.getMessage());
      }
      try {
        AXF_CLS_CTRL_Realization.read(null);
        Assert.fail();
      } catch (AuraHandledException expected) {
        Assert.areEqual('UNAVAILABLE', expected.getMessage());
      }
      try {
        AXF_CLS_CTRL_Realization.reverse(null, 0, 'x');
        Assert.fail();
      } catch (AuraHandledException expected) {
        Assert.areEqual('UNAVAILABLE', expected.getMessage());
      }
      try {
        AXF_CLS_CTRL_Realization.retryFx(null);
        Assert.fail();
      } catch (AuraHandledException expected) {
        Assert.areEqual('UNAVAILABLE', expected.getMessage());
      }
      Test.stopTest();
    }
  }
  @IsTest
  static void manualBankFactIsDistinctAndCannotBeReusedBeyondCapacity() {
    System.runAs(actor()) {
      AXF_OBJ_FinancialTransaction__c target = plan('BRL');
      AXF_OBJ_BankAccount__c bank = new AXF_OBJ_BankAccount__c(
        AXF_BA_LKP_Account__c = target.AXF_FTX_LKP_Account__c,
        AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
        AXF_BA_TXT_CurrencyIsoCode__c = 'BRL'
      );
      insert bank;
      ALT_CLS_RealizationService.Input input = request(
        target.Id,
        40,
        0,
        'bank'
      );
      input.sourceKind = 'BANK';
      input.fundingId = bank.Id;
      ALT_CLS_RealizationService service = new ALT_CLS_RealizationService();
      Test.startTest();
      Id id = service.apply(input);
      AXF_OBJ_ReconciliationAllocation__c allocation = [
        SELECT AXF_RA_LKP_BankTransaction__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE Id = :id
      ];
      Id factId = allocation.AXF_RA_LKP_BankTransaction__c;
      Assert.areEqual(
        1,
        AXF_CLS_CTRL_Realization.sourceVersion(factId, 'BANK')
      );
      input = request(target.Id, 1, 1, 'reuse');
      input.sourceKind = 'BANK';
      input.sourceId = factId;
      input.sourceVersion = 1;
      try {
        service.apply(input);
        Assert.fail('Source amount is exhausted');
      } catch (ALT_CLS_RealizationService.RealizationException expected) {
        Assert.areEqual('UNAVAILABLE_AMOUNT', expected.getMessage());
      }
      Test.stopTest();
      Assert.areEqual(
        'MANUAL',
        [
          SELECT AXF_BAT_PKL_Source__c
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE Id = :factId
        ]
        .AXF_BAT_PKL_Source__c
      );
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c]
      );
    }
  }
  @IsTest
  static void manualCardConsumptionDoesNotSettleInvoice() {
    System.runAs(actor()) {
      AXF_OBJ_FinancialTransaction__c target = plan('BRL');
      AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
        AXF_CC_LKP_Account__c = target.AXF_FTX_LKP_Account__c,
        AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
        AXF_CC_TXT_CurrencyIsoCode__c = 'BRL'
      );
      insert card;
      ALT_CLS_RealizationService.Input input = request(
        target.Id,
        40,
        0,
        'card'
      );
      input.sourceKind = 'CARD';
      input.fundingId = card.Id;
      Test.startTest();
      new ALT_CLS_RealizationService().apply(input);
      ALT_CLS_RealizationService.View result = new ALT_CLS_RealizationService()
        .read(target.Id);
      Test.stopTest();
      Assert.areEqual(40, result.realized);
      Assert.isNotNull(result.allocations[0].AXF_RA_LKP_CardTransaction__c);
      Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FxSettlement__c]);
    }
  }
  @IsTest
  static void sourceCurrencyMismatchHasNoAllocation() {
    System.runAs(actor()) {
      AXF_OBJ_FinancialTransaction__c target = plan('BRL');
      AXF_OBJ_BankAccount__c bank = new AXF_OBJ_BankAccount__c(
        AXF_BA_LKP_Account__c = target.AXF_FTX_LKP_Account__c,
        AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
        AXF_BA_TXT_CurrencyIsoCode__c = 'USD'
      );
      insert bank;
      AXF_OBJ_BankAccountTransaction__c fact = new AXF_OBJ_BankAccountTransaction__c(
        AXF_BAT_MDR_BankAccount__c = bank.Id,
        AXF_BAT_NUM_Magnitude__c = 100,
        AXF_BAT_TXT_CurrencyIsoCode__c = 'USD',
        AXF_BAT_PKL_Direction__c = 'DEBIT',
        AXF_BAT_DAT_Date__c = Date.today(),
        AXF_BAT_EXI_SourceKey__c = 'mismatch',
        AXF_BAT_PKL_Source__c = 'MANUAL',
        AXF_BAT_NUM_Version__c = 0
      );
      insert fact;
      ALT_CLS_RealizationService.Input input = request(
        target.Id,
        40,
        0,
        'mismatch'
      );
      input.sourceKind = 'BANK';
      input.sourceId = fact.Id;
      input.sourceVersion = 0;
      Test.startTest();
      try {
        new ALT_CLS_RealizationService().apply(input);
        Assert.fail('No implicit FX between source and target');
      } catch (ALT_CLS_RealizationService.RealizationException expected) {
        Assert.areEqual('CURRENCY_MISMATCH', expected.getMessage());
      }
      Test.stopTest();
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_ReconciliationAllocation__c]
      );
    }
  }
}
