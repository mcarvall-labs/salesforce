/**
 * @description AXF-11 AC1/AC8. Auth success/failure and the regression guard: no debug log
 * or error message ever contains the apiKey. The apiKey is held only for the current Apex
 * transaction (no persistent cache).
 */
@IsTest
private class AXF_CLS_PluggyAuthServiceTest {
  @IsTest
  static void returnsApiKeyOnSuccess() {
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.apiKey = 'secret-apiKey-value';
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    String key = AXF_CLS_PluggyAuthService.getValidApiKey();
    Test.stopTest();

    System.assertEquals(
      'secret-apiKey-value',
      key,
      'apiKey should be returned to the caller'
    );
  }

  @IsTest
  static void sanitizedErrorNeverLeaksOn401() {
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.authStatus = 401;
    mock.apiKey = 'never-should-appear';
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    try {
      AXF_CLS_PluggyAuthService.getValidApiKey();
      System.assert(false, 'should have thrown');
    } catch (AXF_CLS_PluggyAuthException e) {
      System.assert(
        e.getMessage().contains('HTTP 401'),
        'status surfaced: ' + e.getMessage()
      );
      System.assert(
        !e.getMessage().contains('never-should-appear'),
        'error message must not contain any credential/token'
      );
      System.assert(
        !e.getMessage().toLowerCase().contains('client keys are invalid'),
        'raw response body must not be echoed'
      );
    }
    Test.stopTest();

    String logs = ApexPages.getMessages().toString();
    System.assert(
      !logs.contains('never-should-appear'),
      'no page message leaks the key'
    );
  }

  @IsTest
  static void missingApiKeyInResponseThrowsSanitized() {
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.apiKey = null;
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    try {
      AXF_CLS_PluggyAuthService.getValidApiKey();
      System.assert(false, 'should throw when apiKey absent');
    } catch (AXF_CLS_PluggyAuthException e) {
      System.assert(e.getMessage().contains('apiKey ausente'), e.getMessage());
    }
    Test.stopTest();
  }

  @IsTest
  static void transactionCacheReturnsSameKeyWithoutSecondCallout() {
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.apiKey = 'k1';
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    String a = AXF_CLS_PluggyAuthService.getValidApiKey();
    String b = AXF_CLS_PluggyAuthService.getValidApiKey();
    Test.stopTest();

    System.assertEquals(a, b);
    System.assertEquals(
      1,
      mock.requestedPaths.size(),
      'one POST /auth per transaction'
    );
  }

  @IsTest
  static void invalidateCacheIsSafe() {
    Test.startTest();
    AXF_CLS_PluggyAuthService.invalidateCache(); // must not throw
    Test.stopTest();
  }

  @IsTest
  static void candidateSlotUsesOwnCacheKey() {
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.apiKey = 'candidate-key';
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    String key = AXF_CLS_PluggyAuthService.getValidApiKey(
      AXF_CLS_PluggySettings.NC_CANDIDATE
    );
    Test.stopTest();

    System.assertEquals('candidate-key', key);
  }
}
