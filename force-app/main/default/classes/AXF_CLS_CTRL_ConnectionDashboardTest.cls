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

  private static AXF_OBJ_PluggyConnection__c connection(String status) {
    Account holder = new Account(Name = 'Holder');
    insert holder;
    AXF_OBJ_PluggyConnection__c connection = new AXF_OBJ_PluggyConnection__c(
      AXF_CON_MD_Holder__c = holder.Id,
      AXF_CON_PKL_Institution__c = '341',
      AXF_CON_EXI_PluggyItemId__c = 'item-' + status,
      AXF_CON_PKL_Status__c = status
    );
    insert connection;
    return connection;
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
  static void syncConnectionReportsUnknownAndPausedConnections() {
    ALT_CLS_SyncTestUser.create(
      'axfdunk',
      new List<String>{ 'AXF_OBJ_PluggyConnection__c' }
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_PluggyConnection__c unknown = connection('Active');
      Id missing = unknown.Id;
      delete unknown;
      System.assertEquals(
        'Conexão não encontrada.',
        AXF_CLS_CTRL_ConnectionDashboard.syncConnection(missing).message
      );
      AXF_CLS_CTRL_ConnectionDashboard.SyncView paused = AXF_CLS_CTRL_ConnectionDashboard.syncConnection(
        connection('Paused').Id
      );
      System.assertEquals(false, paused.success);
      System.assertEquals('A conexão está pausada.', paused.message);
    }
  }

  @IsTest
  static void syncConnectionStartsTheBackgroundSync() {
    AXF_OBJ_PluggyConnection__c active = connection('Active');
    ALT_CLS_PluggySyncBatch.chainNextPhase = false;
    Test.startTest();
    AXF_CLS_CTRL_ConnectionDashboard.SyncView view = AXF_CLS_CTRL_ConnectionDashboard.syncConnection(
      active.Id
    );
    System.assertEquals(true, view.success, view.message);
    System.assert(view.message.contains('iniciada'));
    Test.stopTest();
    System.assert(
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'ALT_CLS_PluggySyncBatch'
      ] >= 1
    );
  }

  // Answers the accounts call of whichever item is asked, with an account id of that item.
  private class AccountsMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String url = req.getEndpoint();
      if (url.endsWith('/auth')) {
        res.setBody('{"apiKey":"abc"}');
      } else if (url.contains('/accounts?itemId=')) {
        String item = url.substringAfter('itemId=');
        res.setBody(
          '{"results":[{"id":"acc-' +
            item +
            '","type":"BANK","name":"Conta","number":"1","balance":10}]}'
        );
      } else {
        res.setBody('{"results":[],"next":null}');
      }
      return res;
    }
  }

  @IsTest
  static void syncConnectionSyncsOnlyTheClickedConnection() {
    AXF_OBJ_PluggyConnection__c clicked = connection('Active');
    AXF_OBJ_PluggyConnection__c other = connection('Error');
    ALT_CLS_PluggySyncBatch.chainNextPhase = false;
    ALT_CLS_PluggyAccountSync.assignRecordType = false;
    Test.setMock(HttpCalloutMock.class, new AccountsMock());
    Test.startTest();
    AXF_CLS_CTRL_ConnectionDashboard.syncConnection(clicked.Id);
    Test.stopTest();
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_LKP_Connection__c = :clicked.Id
      ]
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_LKP_Connection__c = :other.Id
      ]
    );
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
