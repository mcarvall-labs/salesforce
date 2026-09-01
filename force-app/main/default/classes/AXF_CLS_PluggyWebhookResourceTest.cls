/**
 * @description AXF-11 / G4-3. Signature is checked before anything is accepted; invalid =>
 * 401 and nothing processed; valid => 200 and AXF_PluggyWebhookEvent__e published (the
 * revalidation runs out of the guest context); payload never stored.
 */
@IsTest
private class AXF_CLS_PluggyWebhookResourceTest {
  static final String SECRET = 'wh-secret';
  static final String BODY = '{"event":"item/updated","itemId":"ITEM_A"}';

  static String sign(String body) {
    return EncodingUtil.convertToHex(
      Crypto.generateMac('HmacSHA256', Blob.valueOf(body), Blob.valueOf(SECRET))
    );
  }

  static RestRequest buildRequest(String body, String signature) {
    RestRequest req = new RestRequest();
    req.requestURI = '/services/apexrest/pluggy/webhook';
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(body);
    if (signature != null) {
      req.headers.put('X-Signature', signature);
    }
    RestContext.request = req;
    RestContext.response = new RestResponse();
    return req;
  }

  @IsTest
  static void rejectsMissingSignature() {
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
  static void rejectsBadSignature() {
    AXF_CLS_PluggyWebhookResource.secretOverrideForTests = SECRET;
    buildRequest(BODY, 'deadbeef');

    Test.startTest();
    AXF_CLS_PluggyWebhookResource.handlePost();
    Test.stopTest();

    System.assertEquals(401, RestContext.response.statusCode);
    System.assert(
      RestContext.response.responseBody.toString().contains('"accepted":false')
    );
  }

  @IsTest
  static void acceptsValidSignatureAndPublishesEvent() {
    AXF_CLS_PluggyWebhookResource.secretOverrideForTests = SECRET;
    // A connection exists so deliver() drives the whole trigger -> handler -> service path.
    AXF_CLS_PluggyTestData.connection('ITEM_A');
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());
    buildRequest(BODY, sign(BODY));

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
  static void webhookDisabledStillValidatesButDoesNotQueue() {
    insert new AXF_PluggyIntegrationConfig__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      AXF_PIC_BOL_WebhookEnabled__c = false
    );
    AXF_CLS_PluggyWebhookResource.secretOverrideForTests = SECRET;
    buildRequest(BODY, sign(BODY));

    Test.startTest();
    AXF_CLS_PluggyWebhookResource.handlePost();
    Test.stopTest();

    System.assertEquals(202, RestContext.response.statusCode);
  }
}
