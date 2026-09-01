/**
 * @description AXF-11 AC6/AC8. The client treats a transport failure as unknown (never
 * success, no blind retry), sanitizes errors, and keeps ids out of user-facing text.
 */
@IsTest
private class AXF_CLS_PluggyHttpClientTest {
  @IsTest
  static void timeoutBecomesUnknownNotSuccess() {
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.throwCallout = true;
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    try {
      new AXF_CLS_PluggyHttpClient().getJson('/items/ITEM_SECRET_ID');
      System.assert(false, 'a callout exception must surface as unknown');
    } catch (AXF_CLS_PluggyIntegrationException e) {
      System.assert(
        e.getMessage().containsIgnoreCase('desconhecido'),
        e.getMessage()
      );
      System.assert(
        !e.getMessage().contains('ITEM_SECRET_ID'),
        'ids stay out of user text'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void successfulGetParsesBody() {
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    AXF_CLS_PluggyHttpClient.PluggyResponse r = new AXF_CLS_PluggyHttpClient()
      .getJson('/items/ITEM_A');
    Test.stopTest();

    System.assertEquals(true, r.isSuccess);
    System.assertEquals('ITEM_OBSERVED_A', String.valueOf(r.body.get('id')));
    System.assertNotEquals(null, r.correlationId);
  }

  @IsTest
  static void sanitizedErrorFormat() {
    String msg = AXF_CLS_PluggyHttpClient.sanitizedError(
      'POST /auth',
      500,
      'abc123'
    );
    System.assert(msg.contains('HTTP 500'));
    System.assert(msg.contains('abc123'));
    System.assert(msg.containsIgnoreCase('sensivel'));
  }

  @IsTest
  static void webhookQueueableRevalidatesConnection() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    System.enqueueJob(new AXF_CLS_PluggyWebhookQueueable('ITEM_A'));
    Test.stopTest();

    System.assertNotEquals(
      null,
      [
        SELECT AXF_CON_DT_ConsentCheckedAt__c
        FROM AXF_OBJ_PluggyConnection__c
        WHERE Id = :c.Id
      ]
      .AXF_CON_DT_ConsentCheckedAt__c
    );
  }

  @IsTest
  static void webhookQueueableIgnoresBlankItem() {
    Test.startTest();
    new AXF_CLS_PluggyWebhookQueueable('').execute(null);
    Test.stopTest();
  }

  @IsTest
  static void settingsWebhookEnabledDefaultsTrue() {
    System.assertEquals(true, AXF_CLS_PluggySettings.webhookEnabled());
    System.assertEquals('NONE', AXF_CLS_PluggySettings.rotationState());
    System.assertEquals(
      'AXF_NC_Pluggy_API',
      AXF_CLS_PluggySettings.activeNamedCredential()
    );
  }
}
