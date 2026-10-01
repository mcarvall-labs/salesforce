@IsTest
private class AXF_CLS_CTRL_PluggyWizardTest {
  private class AuthMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setBody('{"apiKey":"abc"}');
      return res;
    }
  }

  private class SyncMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setBody(
        req.getEndpoint().endsWith('/auth')
          ? '{"apiKey":"abc"}'
          : '{"results":[{"id":"acc-1","type":"BANK","subtype":"CHECKING_ACCOUNT","name":"Conta Corrente","number":"123","bankData":{"transferNumber":"0001/123"}},{"id":"card-1","type":"CREDIT","name":"Gold","number":"5555","creditData":{"brand":"VISA"}}]}'
      );
      return res;
    }
  }

  private class StubVault implements ALT_CLS_PluggyCredential.Vault {
    Boolean present;

    StubVault(Boolean present) {
      this.present = present;
    }

    public Boolean exists() {
      return present;
    }

    public void write(ConnectApi.CredentialInput input) {
    }
  }

  @IsTest
  static void stateReportsCredentials() {
    ALT_CLS_PluggyCredential.vaultForTests = new StubVault(false);
    System.assertEquals(
      false,
      AXF_CLS_CTRL_PluggyWizard.getState().hasCredentials
    );
    ALT_CLS_PluggyCredential.vaultForTests = new StubVault(true);
    System.assertEquals(
      true,
      AXF_CLS_CTRL_PluggyWizard.getState().hasCredentials
    );
  }

  @IsTest
  static void saveCredentialsReturnsResult() {
    ALT_CLS_PluggyCredential.vaultForTests = new StubVault(false);
    System.assertEquals(
      true,
      AXF_CLS_CTRL_PluggyWizard.saveCredentials('id', 'secret').success
    );
    System.assertEquals(
      false,
      AXF_CLS_CTRL_PluggyWizard.saveCredentials('', '').success
    );
  }

  @IsTest
  static void testCredentialsReturnsResult() {
    Test.setMock(HttpCalloutMock.class, new AuthMock());
    AXF_CLS_CTRL_PluggyWizard.StepResult r = AXF_CLS_CTRL_PluggyWizard.testCredentials();
    System.assertEquals(true, r.success);
    System.assertNotEquals(null, r.message);
  }

  @IsTest
  static void createConnectionRejectsMissingData() {
    AXF_CLS_CTRL_PluggyWizard.StepResult r = AXF_CLS_CTRL_PluggyWizard.createConnection(
      null,
      null,
      null
    );
    System.assertEquals(false, r.success);
  }

  @IsTest
  static void stateCountsConnections() {
    ALT_CLS_PluggyCredential.vaultForTests = new StubVault(true);
    System.assertEquals(
      0,
      AXF_CLS_CTRL_PluggyWizard.getState().connectionCount
    );
  }

  @IsTest
  static void syncConnectionRejectsMissingConnection() {
    try {
      AXF_CLS_CTRL_PluggyWizard.syncConnection(null);
      System.assert(false, 'Expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assertNotEquals(null, e.getMessage());
    }
    System.assertEquals(0, AXF_CLS_CTRL_PluggyWizard.getLinked(null).size());
  }

  @IsTest
  static void syncConnectionReturnsLinkedItemsAndState() {
    ALT_CLS_SyncTestUser.create(
      'axfwiz',
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
      ALT_CLS_PluggyCredential.vaultForTests = new StubVault(true);
      Test.setMock(HttpCalloutMock.class, new SyncMock());
      Test.startTest();
      AXF_CLS_CTRL_PluggyWizard.SyncResult r = AXF_CLS_CTRL_PluggyWizard.syncConnection(
        connection.Id
      );
      Test.stopTest();
      System.assertEquals(true, r.success, r.message);
      System.assertEquals(2, r.items.size());
      System.assertEquals('Conta', r.items[0].kind);
      System.assertEquals('0001 / 123', r.items[0].detail);
      System.assertEquals('Cartão', r.items[1].kind);
      System.assertEquals('final 5555', r.items[1].detail);
      System.assertEquals(
        connection.Id,
        AXF_CLS_CTRL_PluggyWizard.getState().latestConnectionId
      );
    }
  }
}
