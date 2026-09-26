@IsTest
private class AXF_CLS_PluggyAuthServiceTest {
  private static AXF_CLS_PluggyTestFactory.MockRouter mockAuth(
    Integer status,
    String body
  ) {
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/auth', status, body);
    Test.setMock(HttpCalloutMock.class, mock);
    return mock;
  }

  @TestSetup
  static void setup() {
    AXF_CLS_PluggyTestFactory.createTestUser();
  }

  @IsTest
  static void getValidApiKeyReturnsKeyFromAuthEndpoint() {
    AXF_CLS_PluggyTestFactory.MockRouter mock = mockAuth(
      200,
      AXF_CLS_PluggyTestFactory.authBody()
    );
    String apiKey;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      apiKey = AXF_CLS_PluggyAuthService.getValidApiKey();
      Test.stopTest();
    }
    Assert.areEqual(
      AXF_CLS_PluggyTestFactory.API_KEY,
      apiKey,
      'API key should come from the /auth response'
    );
    Assert.areEqual(
      'callout:AXF_NC_Pluggy_API/auth',
      mock.endpoints[0],
      'Should call the Named Credential /auth endpoint'
    );
  }

  @IsTest
  static void invalidClientKeysRaiseFriendlyMessage() {
    mockAuth(401, '{"message":"client keys are invalid","code":401}');
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      try {
        AXF_CLS_PluggyAuthService.getValidApiKey();
        Assert.fail('Expected AXF_CLS_PluggyAuthException');
      } catch (AXF_CLS_PluggyAuthException e) {
        Assert.isTrue(
          e.getMessage().contains('HTTP 401: client keys are invalid'),
          e.getMessage()
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void genericHttpErrorRaisesStatusAndBody() {
    mockAuth(500, '{"message":"internal error"}');
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      try {
        AXF_CLS_PluggyAuthService.getValidApiKey();
        Assert.fail('Expected AXF_CLS_PluggyAuthException');
      } catch (AXF_CLS_PluggyAuthException e) {
        Assert.isTrue(e.getMessage().contains('HTTP 500'), e.getMessage());
        Assert.isTrue(
          e.getMessage().contains('internal error'),
          e.getMessage()
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void missingApiKeyInResponseRaises() {
    mockAuth(200, '{"accessToken":"x"}');
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      try {
        AXF_CLS_PluggyAuthService.getValidApiKey();
        Assert.fail('Expected AXF_CLS_PluggyAuthException');
      } catch (AXF_CLS_PluggyAuthException e) {
        Assert.isTrue(
          e.getMessage().contains('não contém um apiKey'),
          e.getMessage()
        );
      }
      Test.stopTest();
    }
  }
}
