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
  static void linkedItemsAreScopedToTheConnectionAndShowTheHolder() {
    ALT_CLS_SyncTestUser.create(
      'axfwiz',
      new List<String>{
        'AXF_OBJ_PluggyConnection__c',
        'AXF_OBJ_BankAccount__c',
        'AXF_OBJ_CreditCard__c'
      }
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      List<AXF_OBJ_PluggyConnection__c> connections = new List<AXF_OBJ_PluggyConnection__c>();
      for (String name : new List<String>{ 'Ana', 'Bia' }) {
        Account holder = new Account(Name = name);
        insert holder;
        connections.add(
          new AXF_OBJ_PluggyConnection__c(
            AXF_CON_MD_Holder__c = holder.Id,
            AXF_CON_PKL_Institution__c = '341',
            AXF_CON_EXI_PluggyItemId__c = 'item-' + name
          )
        );
      }
      insert connections;
      for (AXF_OBJ_PluggyConnection__c connection : connections) {
        insert new AXF_OBJ_BankAccount__c(
          Name = 'Conta ' + connection.Id,
          AXF_BA_MD_Holder__c = connection.AXF_CON_MD_Holder__c,
          AXF_BA_LKP_Connection__c = connection.Id,
          AXF_BA_PKL_Institution__c = '341',
          AXF_BA_PKL_Type__c = 'Checking',
          AXF_BA_TXT_Number__c = '123'
        );
      }
      insert new AXF_OBJ_CreditCard__c(
        Name = 'Cartão',
        AXF_CC_MD_Holder__c = connections[0].AXF_CON_MD_Holder__c,
        AXF_CC_LKP_Connection__c = connections[0].Id,
        AXF_CC_PKL_Institution__c = '341',
        AXF_CC_TXT_LastDigits__c = '5555'
      );
      List<AXF_CLS_CTRL_PluggyWizard.LinkedItem> first = AXF_CLS_CTRL_PluggyWizard.getLinked(
        connections[0].Id
      );
      List<AXF_CLS_CTRL_PluggyWizard.LinkedItem> second = AXF_CLS_CTRL_PluggyWizard.getLinked(
        connections[1].Id
      );
      System.assertEquals(2, first.size());
      System.assertEquals(1, second.size());
      System.assertEquals('Ana', first[0].holder);
      System.assertEquals('Bia', second[0].holder);
      System.assertEquals('- / 123', first[0].detail);
      System.assertEquals('final 5555', first[1].detail);
      System.assertEquals(0, AXF_CLS_CTRL_PluggyWizard.getLinked(null).size());
      System.assertEquals(2, AXF_CLS_CTRL_PluggyWizard.getConnections().size());
    }
  }

  @IsTest
  static void createConnectionWithoutDataReturnsNoConnectionId() {
    AXF_CLS_CTRL_PluggyWizard.StepResult r = AXF_CLS_CTRL_PluggyWizard.createConnection(
      null,
      null,
      null
    );
    System.assertEquals(null, r.connectionId);
  }
}
