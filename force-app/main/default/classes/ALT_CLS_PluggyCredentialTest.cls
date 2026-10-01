@IsTest
private class ALT_CLS_PluggyCredentialTest {
  private class AuthMock implements HttpCalloutMock {
    private Integer status;
    private String body;

    AuthMock(Integer status, String body) {
      this.status = status;
      this.body = body;
    }

    public HttpResponse respond(HttpRequest req) {
      System.assertEquals('POST', req.getMethod());
      System.assert(req.getEndpoint().endsWith('/auth'));
      HttpResponse res = new HttpResponse();
      res.setStatusCode(status);
      res.setBody(body);
      return res;
    }
  }

  private class StubVault implements ALT_CLS_PluggyCredential.Vault {
    Boolean present;
    Boolean fail;
    Integer writes = 0;

    StubVault(Boolean present, Boolean fail) {
      this.present = present;
      this.fail = fail;
    }

    public Boolean exists() {
      return present;
    }

    public void write(ConnectApi.CredentialInput input) {
      writes++;
      if (fail) {
        throw new CalloutException('denied');
      }
      System.assertEquals('AXF_EXC_Pluggy', input.externalCredential);
      System.assertEquals(
        true,
        input.credentials.get('clientSecret').encrypted
      );
    }
  }

  @IsTest
  static void saveRejectsBlankValues() {
    ALT_CLS_PluggyCredential.Result r = new ALT_CLS_PluggyCredential()
      .save('id', ' ');
    System.assertEquals(false, r.success);
  }

  @IsTest
  static void saveForwardsValidValues() {
    StubVault vault = new StubVault(false, false);
    ALT_CLS_PluggyCredential.vaultForTests = vault;
    ALT_CLS_PluggyCredential.Result r = new ALT_CLS_PluggyCredential()
      .save('id', 'secret');
    System.assertEquals(true, r.success);
    System.assertEquals(1, vault.writes);
    System.assert(!r.message.contains('secret'));
  }

  @IsTest
  static void saveReportsVaultFailureWithoutSecret() {
    ALT_CLS_PluggyCredential.vaultForTests = new StubVault(false, true);
    ALT_CLS_PluggyCredential.Result r = new ALT_CLS_PluggyCredential()
      .save('id', 'secret');
    System.assertEquals(false, r.success);
    System.assert(!r.message.contains('secret'));
  }

  @IsTest
  static void hasCredentialsReflectsState() {
    ALT_CLS_PluggyCredential.vaultForTests = new StubVault(false, false);
    System.assertEquals(false, new ALT_CLS_PluggyCredential().hasCredentials());
    ALT_CLS_PluggyCredential.vaultForTests = new StubVault(true, false);
    System.assertEquals(true, new ALT_CLS_PluggyCredential().hasCredentials());
  }

  @IsTest
  static void testAuthenticationSucceedsWithApiKey() {
    Test.setMock(HttpCalloutMock.class, new AuthMock(200, '{"apiKey":"abc"}'));
    System.assertEquals(
      true,
      new ALT_CLS_PluggyCredential().testAuthentication().success
    );
  }

  @IsTest
  static void testAuthenticationReportsInvalidKeys() {
    Test.setMock(
      HttpCalloutMock.class,
      new AuthMock(401, '{"message":"client keys are invalid"}')
    );
    ALT_CLS_PluggyCredential.Result r = new ALT_CLS_PluggyCredential()
      .testAuthentication();
    System.assertEquals(false, r.success);
    System.assert(r.message.contains('inválidos'));
  }

  @IsTest
  static void testAuthenticationReportsOtherErrors() {
    Test.setMock(HttpCalloutMock.class, new AuthMock(500, ''));
    ALT_CLS_PluggyCredential.Result r = new ALT_CLS_PluggyCredential()
      .testAuthentication();
    System.assertEquals(false, r.success);
    System.assert(r.message.contains('500'));
  }
}
