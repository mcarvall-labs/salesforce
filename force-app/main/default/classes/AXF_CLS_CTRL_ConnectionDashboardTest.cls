@IsTest
private class AXF_CLS_CTRL_ConnectionDashboardTest {
  @TestSetup
  static void setup() {
    ALT_CLS_ConnectionTestUser.create('axfctrl');
  }

  private static User controllerUser() {
    return ALT_CLS_ConnectionTestUser.find('axfctrl');
  }

  @IsTest
  static void getDashboardReturnsCountersAndRows() {
    System.runAs(controllerUser()) {
      Account holder = new Account(Name = 'Holder');
      insert holder;
      insert new AXF_OBJ_PluggyConnection__c(
        AXF_CON_MD_Holder__c = holder.Id,
        AXF_CON_PKL_Institution__c = '341',
        AXF_CON_EXI_PluggyItemId__c = 'item-1',
        AXF_CON_PKL_Status__c = 'Error'
      );
      AXF_CLS_CTRL_ConnectionDashboard.DashboardData data = AXF_CLS_CTRL_ConnectionDashboard.getDashboard();
      System.assertEquals(0, data.active);
      System.assertEquals(1, data.error);
      System.assertEquals(0, data.paused);
      System.assertEquals(1, data.rows.size());
      System.assertEquals('Holder', data.rows[0].holder);
    }
  }

  private class SyncMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setBody(
        req.getEndpoint().endsWith('/auth')
          ? '{"apiKey":"abc"}'
          : '{"results":[{"id":"acc-1","type":"BANK","name":"Conta","number":"1","balance":10}]}'
      );
      return res;
    }
  }

  @IsTest
  static void syncConnectionRejectsMissingId() {
    try {
      AXF_CLS_CTRL_ConnectionDashboard.syncConnection(null);
      System.assert(false, 'Expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assertNotEquals(null, e.getMessage());
    }
  }

  @IsTest
  static void syncConnectionReportsUnknownConnection() {
    ALT_CLS_SyncTestUser.create(
      'axfdunk',
      new List<String>{ 'AXF_OBJ_PluggyConnection__c' }
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account holder = new Account(Name = 'Holder');
      insert holder;
      AXF_OBJ_PluggyConnection__c connection = new AXF_OBJ_PluggyConnection__c(
        AXF_CON_MD_Holder__c = holder.Id,
        AXF_CON_PKL_Institution__c = '341',
        AXF_CON_EXI_PluggyItemId__c = 'gone'
      );
      insert connection;
      Id missing = connection.Id;
      delete connection;
      System.assertEquals(
        false,
        AXF_CLS_CTRL_ConnectionDashboard.syncConnection(missing).success
      );
    }
  }

  @IsTest
  static void syncConnectionBringsAccountsAndSummarizesTheResult() {
    ALT_CLS_SyncTestUser.create(
      'axfdsync',
      new List<String>{
        'AXF_OBJ_PluggyConnection__c',
        'AXF_OBJ_BankAccount__c',
        'AXF_OBJ_CreditCard__c'
      }
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account holder = new Account(Name = 'Holder');
      insert holder;
      AXF_OBJ_PluggyConnection__c connection = new AXF_OBJ_PluggyConnection__c(
        AXF_CON_MD_Holder__c = holder.Id,
        AXF_CON_PKL_Institution__c = '341',
        AXF_CON_EXI_PluggyItemId__c = 'item-1'
      );
      insert connection;
      ALT_CLS_PluggyAccountSync.assignRecordType = false;
      Test.setMock(HttpCalloutMock.class, new SyncMock());
      Test.startTest();
      AXF_CLS_CTRL_ConnectionDashboard.SyncView view = AXF_CLS_CTRL_ConnectionDashboard.syncConnection(
        connection.Id
      );
      Test.stopTest();
      System.assertEquals(true, view.success, view.message);
      System.assert(view.message.contains('1 contas e 0 cartões'));
      System.assertEquals(1, [SELECT COUNT() FROM AXF_OBJ_BankAccount__c]);
    }
  }

  @IsTest
  static void dashboardIsDeniedToAUserWithoutAccess() {
    User restricted = new User(
      Alias = 'axfnodsh',
      Email = 'axfnodsh@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'NoDash',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
      .Id,
      TimeZoneSidKey = 'America/Sao_Paulo',
      Username = 'axfnodsh' + System.currentTimeMillis() + '@example.com'
    );
    insert restricted;
    Boolean denied = false;
    System.runAs(restricted) {
      try {
        AXF_CLS_CTRL_ConnectionDashboard.getDashboard();
      } catch (QueryException e) {
        denied = true;
      }
    }
    System.assertEquals(true, denied);
  }
}
