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
}
