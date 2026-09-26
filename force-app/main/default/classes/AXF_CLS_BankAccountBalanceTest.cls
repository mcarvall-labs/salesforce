/**
 * @description Tests for the real-time balance refresh: ALT_CLS_BankAccountBalance (business
 * service), AXF_CLS_CTRL_RealTimeBalance (current LWC controller) and the legacy
 * AXF_CLS_BankAccountBalanceController.
 */
@IsTest
private class AXF_CLS_BankAccountBalanceTest {
  @TestSetup
  static void setup() {
    User u = AXF_CLS_PluggyTestFactory.createTestUser();
    System.runAs(u) {
      AXF_CLS_PluggyTestFactory.createStandardData();
    }
  }

  private static Id bankAccountId() {
    return [
      SELECT Id
      FROM AXF_OBJ_BankAccount__c
      WHERE
        AXF_BA_EXI_PluggyAccountId__c = :AXF_CLS_PluggyTestFactory.BANK_PLUGGY_ID
    ]
    .Id;
  }

  private static void mockBalance(Integer status, String body) {
    Test.setMock(
      HttpCalloutMock.class,
      new AXF_CLS_PluggyTestFactory.MockRouter()
        .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody())
        .route('/accounts/', status, body)
    );
  }

  private static AXF_OBJ_BankAccount__c reload(Id recordId) {
    return [
      SELECT AXF_BA_CUR_Balance__c, AXF_BA_DAT_LastSync__c
      FROM AXF_OBJ_BankAccount__c
      WHERE Id = :recordId
    ];
  }

  // ------------------------------------------------------------ ALT_CLS_BankAccountBalance

  @IsTest
  static void serviceRefreshUpdatesBalanceAndLastSync() {
    mockBalance(200, AXF_CLS_PluggyTestFactory.balanceBody(2345.67));
    Id baId = bankAccountId();
    ALT_CLS_BankAccountBalance.BalanceRefreshResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = new ALT_CLS_BankAccountBalance().refreshBalance(baId);
      Test.stopTest();
    }
    Assert.isTrue(result.isSuccess, result.message);
    Assert.areEqual(2345.67, result.balance);
    Assert.areEqual('BRL', result.currencyCode);
    Assert.areEqual('Saldo atualizado com sucesso.', result.message);
    AXF_OBJ_BankAccount__c saved = reload(baId);
    Assert.areEqual(2345.67, saved.AXF_BA_CUR_Balance__c);
    Assert.areEqual(
      Datetime.newInstanceGmt(2026, 9, 20, 10, 0, 0),
      saved.AXF_BA_DAT_LastSync__c
    );
  }

  @IsTest
  static void serviceRefreshDefaultsLastSyncToNowWhenMissing() {
    mockBalance(200, '{"id":"x","balance":10.5,"currency":"BRL"}');
    Id baId = bankAccountId();
    Datetime before = Datetime.now().addSeconds(-1);
    ALT_CLS_BankAccountBalance.BalanceRefreshResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = new ALT_CLS_BankAccountBalance().refreshBalance(baId);
      Test.stopTest();
    }
    Assert.isTrue(result.isSuccess);
    Assert.isTrue(result.lastSync >= before, 'Falls back to now');
  }

  @IsTest
  static void serviceRefreshReportsHttpErrorWithoutUpdating() {
    mockBalance(500, '{}');
    Id baId = bankAccountId();
    ALT_CLS_BankAccountBalance.BalanceRefreshResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = new ALT_CLS_BankAccountBalance().refreshBalance(baId);
      Test.stopTest();
    }
    Assert.isFalse(result.isSuccess);
    Assert.isTrue(
      result.message.startsWith('Erro ao atualizar saldo'),
      result.message
    );
    Assert.isNull(reload(baId).AXF_BA_CUR_Balance__c);
  }

  // ------------------------------------------------------------ AXF_CLS_CTRL_RealTimeBalance

  @IsTest
  static void controllerMapsBusinessResult() {
    mockBalance(200, AXF_CLS_PluggyTestFactory.balanceBody(99.99));
    Id baId = bankAccountId();
    AXF_CLS_CTRL_RealTimeBalance.BalanceRefreshResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = AXF_CLS_CTRL_RealTimeBalance.refreshBalance(baId);
      Test.stopTest();
    }
    Assert.isTrue(result.isSuccess);
    Assert.areEqual(99.99, result.balance);
    Assert.areEqual('BRL', result.currencyCode);
    Assert.isNotNull(result.lastSync);
    Assert.areEqual('Saldo atualizado com sucesso.', result.message);
  }

  @IsTest
  static void controllerRejectsNullIdAndWrapsErrors() {
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      AXF_OBJ_BankAccount__c gone = AXF_CLS_PluggyTestFactory.createBankAccount(
        null,
        null,
        'acc-gone'
      );
      delete gone;
      Test.startTest();
      try {
        AXF_CLS_CTRL_RealTimeBalance.refreshBalance(null);
        Assert.fail('Expected AuraHandledException');
      } catch (AuraHandledException e) {
        Assert.isNotNull(e);
      }
      try {
        AXF_CLS_CTRL_RealTimeBalance.refreshBalance(gone.Id);
        Assert.fail('Expected AuraHandledException');
      } catch (AuraHandledException e) {
        Assert.isNotNull(e, 'Missing record is wrapped for the LWC');
      }
      Test.stopTest();
    }
  }

  // ------------------------------------------------------------ AXF_CLS_BankAccountBalanceController (legacy)

  @IsTest
  static void legacyControllerRefreshesBalance() {
    mockBalance(200, AXF_CLS_PluggyTestFactory.balanceBody(500.25));
    Id baId = bankAccountId();
    AXF_CLS_BankAccountBalanceController.BalanceRefreshResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = AXF_CLS_BankAccountBalanceController.refreshBalance(baId);
      Test.stopTest();
    }
    Assert.isTrue(result.isSuccess, result.message);
    Assert.areEqual(500.25, result.balance);
    Assert.areEqual(500.25, reload(baId).AXF_BA_CUR_Balance__c);
  }

  @IsTest
  static void legacyControllerReportsErrors() {
    mockBalance(404, '{}');
    Id baId = bankAccountId();
    AXF_CLS_BankAccountBalanceController.BalanceRefreshResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = AXF_CLS_BankAccountBalanceController.refreshBalance(baId);
      Test.stopTest();
    }
    Assert.isFalse(result.isSuccess);
    Assert.isTrue(result.message.contains('HTTP 404'), result.message);
  }
}
