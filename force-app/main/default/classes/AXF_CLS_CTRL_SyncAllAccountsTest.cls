@IsTest
private class AXF_CLS_CTRL_SyncAllAccountsTest {
  @TestSetup
  static void setup() {
    User u = AXF_CLS_PluggyTestFactory.createTestUser();
    System.runAs(u) {
      AXF_OBJ_BankInstitution__c inst = AXF_CLS_PluggyTestFactory.createInstitution(
        'Banco do Brasil (001)',
        '001'
      );
      AXF_CLS_PluggyTestFactory.createHolder(
        'Joao Silva',
        AXF_CLS_PluggyTestFactory.CPF
      );
      AXF_CLS_PluggyTestFactory.createConnection(
        inst.Id,
        AXF_CLS_PluggyTestFactory.ITEM_ID
      );
    }
  }

  @IsTest
  static void performSyncMapsBusinessResult() {
    Test.setMock(
      HttpCalloutMock.class,
      AXF_CLS_PluggyTestFactory.itemSyncMock()
    );
    AXF_CLS_CTRL_SyncAllAccounts.SyncExecutionResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = AXF_CLS_CTRL_SyncAllAccounts.performSync();
      Test.stopTest();
    }
    Assert.isTrue(result.isSuccess, result.message);
    Assert.areEqual(1, result.connectionsProcessed);
    Assert.areEqual(1, result.bankAccountsSynced);
    Assert.areEqual(1, result.creditCardsSynced);
    Assert.areEqual(0, result.transactionsSynced);
    Assert.areEqual(0, result.invoicesSynced);
    Assert.isTrue(result.errors.isEmpty());
    Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_BankAccount__c]);
  }

  @IsTest
  static void performSyncReturnsFailureResultWhenAuthFails() {
    Test.setMock(
      HttpCalloutMock.class,
      new AXF_CLS_PluggyTestFactory.MockRouter()
        .route('/auth', 500, '{"message":"unavailable"}')
    );
    AXF_CLS_CTRL_SyncAllAccounts.SyncExecutionResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = AXF_CLS_CTRL_SyncAllAccounts.performSync();
      Test.stopTest();
    }
    Assert.isFalse(result.isSuccess);
    Assert.isTrue(result.message.contains('HTTP 500'), result.message);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_BankAccount__c]);
  }
}
