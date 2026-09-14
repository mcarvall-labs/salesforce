/**
 * @description AXF-105: the realization triggers dispatch through explicit handlers while every
 * externally observable protection of ALT_CLS_RealizationGuard is preserved (service-only writes,
 * immutable referenced originals, forged financial roles, recognition evidence, bulk 200 rows).
 */
@IsTest
private class AXF_CLS_RealizationTriggerHandlerTest {
  private static final Integer BATCH_SIZE = 200;

  private static User actor() {
    return [SELECT Id FROM User WHERE Alias = 'axf105' LIMIT 1];
  }

  @TestSetup
  static void setup() {
    User actor = new User(
      Alias = 'axf105',
      Email = 'axf105@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Trigger Handler Tester',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
      .Id,
      Username = 'axf105.' + System.now().getTime() + '@example.invalid'
    );
    insert actor;
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
    }
    insert assignments;
    PermissionSet capability = new PermissionSet(
      Name = 'AXF105TestCapability',
      Label = 'AXF105 test capability'
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
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new AXF_ReportCurrencyPref__c(
        SetupOwnerId = UserInfo.getOrganizationId(),
        AXF_RCP_TXT_IsoCode__c = 'BRL'
      );
    }
  }

  @IsTest
  static void bulkDirectAllocationWritesAreRejectedInEveryContext() {
    System.runAs(actor()) {
      AXF_OBJ_FinancialTransaction__c target = plan('BRL');
      Id allocationId = new ALT_CLS_RealizationService()
        .apply(request(target.Id, 10, 0, 'axf105-seed'));
      AXF_OBJ_ReconciliationAllocation__c seed = [
        SELECT AXF_RA_LKP_ManualTransaction__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE Id = :allocationId
      ];
      List<AXF_OBJ_ReconciliationAllocation__c> forged = new List<AXF_OBJ_ReconciliationAllocation__c>();
      for (Integer i = 0; i < BATCH_SIZE; i++) {
        forged.add(
          new AXF_OBJ_ReconciliationAllocation__c(
            AXF_RA_LKP_FinancialTransaction__c = target.Id,
            AXF_RA_LKP_ManualTransaction__c = seed.AXF_RA_LKP_ManualTransaction__c,
            AXF_RA_NUM_Magnitude__c = 1
          )
        );
      }
      Test.startTest();
      Database.SaveResult[] inserts = Database.insert(forged, false);
      Database.SaveResult[] updates = Database.update(
        new List<AXF_OBJ_ReconciliationAllocation__c>{
          new AXF_OBJ_ReconciliationAllocation__c(
            Id = allocationId,
            AXF_RA_NUM_Magnitude__c = 20
          )
        },
        false
      );
      Database.DeleteResult[] deletes = Database.delete(
        new List<AXF_OBJ_ReconciliationAllocation__c>{
          new AXF_OBJ_ReconciliationAllocation__c(Id = allocationId)
        },
        false
      );
      Test.stopTest();
      Assert.areEqual(BATCH_SIZE, inserts.size());
      for (Database.SaveResult result : inserts) {
        Assert.isFalse(result.isSuccess(), 'Direct allocation insert');
        Assert.isTrue(
          result.getErrors()[0].getMessage().contains('realization service')
        );
      }
      Assert.isFalse(updates[0].isSuccess(), 'Direct allocation update');
      Assert.isFalse(deletes[0].isSuccess(), 'Historical effect delete');
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM AXF_OBJ_ReconciliationAllocation__c]
      );
    }
  }

  @IsTest
  static void bulkForgedFinancialRolesAreRejectedAndPlannedRowsSucceed() {
    System.runAs(actor()) {
      Account holder = holder();
      List<AXF_OBJ_FinancialTransaction__c> rows = new List<AXF_OBJ_FinancialTransaction__c>();
      for (Integer i = 0; i < BATCH_SIZE; i++) {
        AXF_OBJ_FinancialTransaction__c row = plannedRow(
          holder.Id,
          'axf105-role-' + i
        );
        row.AXF_FTX_PKL_PlanKind__c = Math.mod(i, 2) == 0
          ? 'CASH_FACT'
          : 'PLANNED';
        rows.add(row);
      }
      Test.startTest();
      Database.SaveResult[] results = Database.insert(rows, false);
      Test.stopTest();
      Integer rejected = 0;
      for (Integer i = 0; i < BATCH_SIZE; i++) {
        if (Math.mod(i, 2) == 0) {
          Assert.isFalse(results[i].isSuccess(), 'Forged role ' + i);
          rejected++;
        } else {
          Assert.isTrue(results[i].isSuccess(), 'Planned row ' + i);
        }
      }
      Assert.areEqual(BATCH_SIZE / 2, rejected);
      Assert.areEqual(
        BATCH_SIZE / 2,
        [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c]
      );
      List<AXF_OBJ_FinancialTransaction__c> saved = [
        SELECT Id, AXF_FTX_PKL_PlanKind__c
        FROM AXF_OBJ_FinancialTransaction__c
      ];
      for (AXF_OBJ_FinancialTransaction__c row : saved) {
        row.AXF_FTX_PKL_PlanKind__c = 'CASH_FACT';
      }
      for (Database.SaveResult result : Database.update(saved, false)) {
        Assert.isFalse(result.isSuccess(), 'Financial role is immutable');
      }
    }
  }

  @IsTest
  static void referencedOriginalsStayImmutableWhileUnreferencedRowsRemainEditable() {
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
        'axf105-bank'
      );
      input.sourceKind = 'BANK';
      input.fundingId = bank.Id;
      Id allocationId = new ALT_CLS_RealizationService().apply(input);
      Id bankFactId = [
        SELECT AXF_RA_LKP_BankTransaction__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE Id = :allocationId
      ]
      .AXF_RA_LKP_BankTransaction__c;
      AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
        AXF_CC_LKP_Account__c = target.AXF_FTX_LKP_Account__c,
        AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
        AXF_CC_TXT_CurrencyIsoCode__c = 'BRL'
      );
      insert card;
      input = request(target.Id, 20, 1, 'axf105-card');
      input.sourceKind = 'CARD';
      input.fundingId = card.Id;
      Id cardAllocationId = new ALT_CLS_RealizationService().apply(input);
      Id cardFactId = [
        SELECT AXF_RA_LKP_CardTransaction__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE Id = :cardAllocationId
      ]
      .AXF_RA_LKP_CardTransaction__c;
      AXF_OBJ_FinancialTransaction__c free = plannedRow(
        target.AXF_FTX_LKP_Account__c,
        'axf105-free'
      );
      insert free;
      Test.startTest();
      AXF_OBJ_CreditCardTransaction__c cardFact = new AXF_OBJ_CreditCardTransaction__c(
        Id = cardFactId,
        AXF_CCT_NUM_Magnitude__c = 999
      );
      Assert.isFalse(
        Database.update(cardFact, false).isSuccess(),
        'Referenced card fact content'
      );
      Assert.isFalse(
        Database.delete(cardFact, false).isSuccess(),
        'Referenced card fact delete'
      );
      AXF_OBJ_BankAccountTransaction__c fact = new AXF_OBJ_BankAccountTransaction__c(
        Id = bankFactId,
        AXF_BAT_NUM_Magnitude__c = 999
      );
      Assert.isFalse(
        Database.update(fact, false).isSuccess(),
        'Referenced bank fact content'
      );
      Assert.isFalse(
        Database.delete(fact, false).isSuccess(),
        'Referenced bank fact delete'
      );
      target.AXF_FTX_NUM_Magnitude__c = 200;
      Assert.isFalse(
        Database.update(target, false).isSuccess(),
        'Referenced plan content'
      );
      Assert.isFalse(
        Database.delete(target, false).isSuccess(),
        'Referenced plan delete'
      );
      free.AXF_FTX_NUM_Magnitude__c = 55;
      Assert.isTrue(
        Database.update(free, false).isSuccess(),
        'Unreferenced plan stays editable'
      );
      Assert.isTrue(
        Database.delete(free, false).isSuccess(),
        'Unreferenced plan can be deleted'
      );
      Test.stopTest();
      Assert.areEqual(
        40,
        [
          SELECT AXF_BAT_NUM_Magnitude__c
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE Id = :bankFactId
        ]
        .AXF_BAT_NUM_Magnitude__c
      );
    }
  }

  @IsTest
  static void recognitionEvidenceOutsideTheServiceIsRejectedAndSnapshotsStayImmutable() {
    System.runAs(actor()) {
      AXF_OBJ_FinancialTransaction__c target = plan('BRL');
      Id allocationId = new ALT_CLS_RealizationService()
        .apply(request(target.Id, 10, 0, 'axf105-fx'));
      List<AXF_OBJ_FxApplicationSnapshot__c> forged = new List<AXF_OBJ_FxApplicationSnapshot__c>();
      for (Integer i = 0; i < BATCH_SIZE; i++) {
        forged.add(
          new AXF_OBJ_FxApplicationSnapshot__c(
            AXF_FXS_LKP_ReconciliationAllocation__c = allocationId,
            AXF_FXS_PKL_TargetType__c = 'RECONCILIATION_ALLOCATION',
            AXF_FXS_PKL_Purpose__c = 'RECOGNITION',
            AXF_FXS_PKL_State__c = 'ACTIVE',
            AXF_FXS_EXI_ApplicationKey__c = 'axf105-forged-' + i,
            AXF_FXS_NUM_OriginalAmount__c = 10,
            AXF_FXS_NUM_ReportingAmount__c = 10,
            AXF_FXS_NUM_Revision__c = 1,
            AXF_FXS_NUM_Version__c = 1,
            AXF_FXS_TXT_CurrencyIsoCode__c = 'BRL',
            AXF_FXS_TXT_OriginalIso__c = 'BRL'
          )
        );
      }
      Test.startTest();
      Database.SaveResult[] inserts = Database.insert(forged, false);
      Test.stopTest();
      Assert.areEqual(BATCH_SIZE, inserts.size());
      for (Database.SaveResult result : inserts) {
        Assert.isFalse(result.isSuccess(), 'Forged recognition evidence');
        Assert.isTrue(
          result.getErrors()[0].getMessage().contains('realization service')
        );
      }
      AXF_OBJ_FxApplicationSnapshot__c history = new AXF_OBJ_FxApplicationSnapshot__c(
        AXF_FXS_LKP_FinancialTransaction__c = target.Id,
        AXF_FXS_PKL_TargetType__c = 'FINANCIAL_TRANSACTION',
        AXF_FXS_PKL_Purpose__c = 'CURRENT_REVALUATION',
        AXF_FXS_PKL_State__c = 'SUPERSEDED',
        AXF_FXS_EXI_ApplicationKey__c = 'axf105-history',
        AXF_FXS_NUM_OriginalAmount__c = 10,
        AXF_FXS_NUM_ReportingAmount__c = 10,
        AXF_FXS_NUM_Revision__c = 1,
        AXF_FXS_NUM_Version__c = 1,
        AXF_FXS_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_FXS_TXT_OriginalIso__c = 'BRL'
      );
      Assert.isTrue(
        Database.insert(history, false).isSuccess(),
        'Non-recognition snapshot insert stays allowed'
      );
      history.AXF_FXS_NUM_Version__c = 2;
      Assert.isFalse(
        Database.update(history, false).isSuccess(),
        'SUPERSEDED history is immutable'
      );
      List<AXF_OBJ_FxApplicationSnapshot__c> existing = [
        SELECT Id, AXF_FXS_PKL_State__c
        FROM AXF_OBJ_FxApplicationSnapshot__c
        WHERE AXF_FXS_LKP_ReconciliationAllocation__c = :allocationId
      ];
      for (AXF_OBJ_FxApplicationSnapshot__c snapshot : existing) {
        Assert.isFalse(
          Database.delete(snapshot, false).isSuccess(),
          'Snapshot delete'
        );
        snapshot.AXF_FXS_NUM_OriginalAmount__c = 1;
        Assert.isFalse(
          Database.update(snapshot, false).isSuccess(),
          'Snapshot content'
        );
        snapshot.AXF_FXS_NUM_OriginalAmount__c = null;
        snapshot.AXF_FXS_PKL_State__c = 'CANCELLED';
        Assert.isFalse(
          Database.update(snapshot, false).isSuccess(),
          'Invalid state transition'
        );
      }
    }
  }

  private static Account holder() {
    Account holder = new Account(
      Name = 'Trigger handler holder',
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert holder;
    return holder;
  }

  private static AXF_OBJ_FinancialTransaction__c plannedRow(
    Id holderId,
    String key
  ) {
    return new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = holderId,
      AXF_FTX_NUM_Magnitude__c = 100,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = Date.today(),
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_NUM_Version__c = 0,
      AXF_FTX_EXI_ClientRequestId__c = String.valueOf(holderId) + '-' + key
    );
  }

  private static AXF_OBJ_FinancialTransaction__c plan(String iso) {
    AXF_OBJ_FinancialTransaction__c result = plannedRow(holder().Id, 'plan');
    result.AXF_FTX_TXT_CurrencyIsoCode__c = iso;
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
}
