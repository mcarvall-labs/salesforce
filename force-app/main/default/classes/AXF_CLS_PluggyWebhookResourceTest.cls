/**
 * @description AXF-11 / G4-3. The shared-secret header is checked before anything is
 * accepted; missing/wrong => 401 and nothing processed; valid => 200 and
 * AXF_PluggyWebhookEvent__e published (the revalidation runs out of the guest context);
 * payload never stored.
 */
@IsTest
private class AXF_CLS_PluggyWebhookResourceTest {
  static final String SECRET = 'wh-secret-value';
  static final String BODY = '{"event":"item/updated","itemId":"ITEM_A"}';

  static RestRequest buildRequest(String body, String token) {
    RestRequest req = new RestRequest();
    req.requestURI = '/services/apexrest/pluggy/webhook';
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(body);
    if (token != null) {
      req.headers.put('X-Webhook-Token', token);
    }
    RestContext.request = req;
    RestContext.response = new RestResponse();
    return req;
  }

  @IsTest
  static void rejectsMissingToken() {
    AXF_CLS_PluggyWebhookResource.secretOverrideForTests = SECRET;
    buildRequest(BODY, null);

    Test.startTest();
    AXF_CLS_PluggyWebhookResource.handlePost();
    Test.stopTest();

    System.assertEquals(401, RestContext.response.statusCode);
    System.assert(
      RestContext.response.responseBody.toString().contains('"accepted":false'),
      'nothing processed on a rejected webhook'
    );
  }

  @IsTest
  static void rejectsWrongToken() {
    AXF_CLS_PluggyWebhookResource.secretOverrideForTests = SECRET;
    buildRequest(BODY, 'not-the-secret');

    Test.startTest();
    AXF_CLS_PluggyWebhookResource.handlePost();
    Test.stopTest();

    System.assertEquals(401, RestContext.response.statusCode);
    System.assert(
      RestContext.response.responseBody.toString().contains('"accepted":false')
    );
  }

  @IsTest
  static void acceptsValidTokenAndPublishesEvent() {
    AXF_CLS_PluggyWebhookResource.secretOverrideForTests = SECRET;
    // A connection exists so deliver() drives the whole trigger -> handler -> service path.
    AXF_CLS_PluggyTestData.connection('ITEM_A');
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());
    buildRequest(BODY, SECRET);

    Test.startTest();
    AXF_CLS_PluggyWebhookResource.handlePost();
    Test.getEventBus().deliver(); // runs AXF_TRG_PluggyWebhookEvent
    Test.stopTest();

    System.assertEquals(200, RestContext.response.statusCode);
    System.assert(
      RestContext.response.responseBody.toString().contains('"queued":true'),
      RestContext.response.responseBody.toString()
    );
  }

  @IsTest
  static void acceptsBearerPrefixedToken() {
    AXF_CLS_PluggyWebhookResource.secretOverrideForTests = SECRET;
    RestRequest req = new RestRequest();
    req.requestURI = '/services/apexrest/pluggy/webhook';
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(BODY);
    req.headers.put('Authorization', 'Bearer ' + SECRET);
    RestContext.request = req;
    RestContext.response = new RestResponse();
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    AXF_CLS_PluggyWebhookResource.handlePost();
    Test.stopTest();

    System.assertEquals(200, RestContext.response.statusCode);
  }

  @IsTest
  static void validWebhookAlwaysQueuesForNonGuestProcessing() {
    insert new AXF_PluggyIntegrationConfig__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      AXF_PIC_BOL_WebhookEnabled__c = false
    );
    AXF_CLS_PluggyWebhookResource.secretOverrideForTests = SECRET;
    buildRequest(BODY, SECRET);

    Test.startTest();
    AXF_CLS_PluggyWebhookResource.handlePost();
    Test.stopTest();

    System.assertEquals(200, RestContext.response.statusCode);
    System.assert(
      RestContext.response.responseBody.toString().contains('"queued":true'),
      RestContext.response.responseBody.toString()
    );
  }
}
