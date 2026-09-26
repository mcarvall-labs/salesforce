@IsTest
private class AXF_CLS_CTRL_PluggyManualSyncTest {
  @TestSetup
  static void setup() {
    User u = AXF_CLS_PluggyTestFactory.createTestUser();
    System.runAs(u) {
      AXF_CLS_PluggyTestFactory.createStandardData();
    }
  }

  @IsTest
  static void syncRecordDelegatesToBusinessServiceAndMapsResult() {
    Test.setMock(
      HttpCalloutMock.class,
      new AXF_CLS_PluggyTestFactory.MockRouter()
        .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody())
        .route(
          '/v2/transactions',
          200,
          AXF_CLS_PluggyTestFactory.txBody(
            new List<Object>{
              AXF_CLS_PluggyTestFactory.txJson(
                'tx-1',
                AXF_CLS_PluggyTestFactory.BANK_PLUGGY_ID,
                -10.0,
                null
              ),
              AXF_CLS_PluggyTestFactory.txJson(
                'tx-2',
                AXF_CLS_PluggyTestFactory.BANK_PLUGGY_ID,
                -20.0,
                null
              )
            },
            null
          )
        )
    );
    Id baId = [SELECT Id FROM AXF_OBJ_BankAccount__c LIMIT 1].Id;
    AXF_CLS_CTRL_PluggyManualSync.SyncExecutionResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = AXF_CLS_CTRL_PluggyManualSync.syncRecord(
        baId,
        'AXF_OBJ_BankAccount__c',
        Date.newInstance(2026, 9, 1),
        Date.newInstance(2026, 9, 30)
      );
      Test.stopTest();
    }
    Assert.isTrue(result.isSuccess, result.message);
    Assert.areEqual(2, result.transactionsSynced);
    Assert.areEqual(0, result.invoicesSynced);
    Assert.areEqual(0, result.bankAccountsSynced);
    Assert.areEqual(0, result.creditCardsSynced);
    Assert.areEqual(0, result.connectionsProcessed);
    Assert.isTrue(result.errors.isEmpty());
    Assert.isTrue(
      result.message.contains('2 transações bancárias sincronizadas'),
      result.message
    );
  }

  @IsTest
  static void syncRecordValidatesRequiredParameters() {
    Id baId = [SELECT Id FROM AXF_OBJ_BankAccount__c LIMIT 1].Id;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      try {
        AXF_CLS_CTRL_PluggyManualSync.syncRecord(
          null,
          'AXF_OBJ_BankAccount__c',
          null,
          null
        );
        Assert.fail('Expected AuraHandledException for missing record id');
      } catch (AuraHandledException e) {
        Assert.isNotNull(e);
      }
      try {
        AXF_CLS_CTRL_PluggyManualSync.syncRecord(baId, ' ', null, null);
        Assert.fail('Expected AuraHandledException for missing sObject type');
      } catch (AuraHandledException e) {
        Assert.isNotNull(e);
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void syncRecordWrapsUnexpectedErrors() {
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      AXF_OBJ_BankAccount__c gone = AXF_CLS_PluggyTestFactory.createBankAccount(
        null,
        null,
        'acc-gone'
      );
      delete gone;
      Test.startTest();
      try {
        AXF_CLS_CTRL_PluggyManualSync.syncRecord(
          gone.Id,
          'AXF_OBJ_BankAccount__c',
          null,
          null
        );
        Assert.fail('Expected AuraHandledException');
      } catch (AuraHandledException e) {
        Assert.isNotNull(e, 'Query failure is wrapped for the LWC');
      }
      Test.stopTest();
    }
  }
}
