/**
 * @description Inbound Pluggy webhook endpoint. Fechamento G4-3:
 *   - the HMAC signature of the raw body is verified BEFORE anything is accepted;
 *   - an invalid signature returns 401 and nothing is processed or logged (only status +
 *     correlation id);
 *   - a valid payload ONLY publishes AXF_PluggyWebhookEvent__e (handled out of the guest
 *     context by AXF_TRG_PluggyWebhookEvent); the payload is never written as a fact.
 *
 * This runs as the Site guest user, whose license forbids writing to
 * AXF_OBJ_PluggyConnection__c and using the External Credential — so the guest only
 * verifies + publishes, and AXF_CLS_PluggyWebhookEventHandler does the callout + write.
 *
 * Exposing this at a public URL (Site + guest user, or a Connected App) is a manual install
 * step (AXF-77). The class, the verification and the tests are the deliverable.
 */
@RestResource(urlMapping='/pluggy/webhook')
global with sharing class AXF_CLS_PluggyWebhookResource {
  @TestVisible
  private static final List<String> SIGNATURE_HEADERS = new List<String>{
    'X-Signature',
    'X-Webhook-Signature',
    'X-Hub-Signature-256'
  };

  @HttpPost
  global static void handlePost() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    String correlationId = AXF_CLS_PluggyHttpClient.newCorrelationId();
    res.addHeader('X-Request-Id', correlationId);

    String rawBody = (req.requestBody == null)
      ? null
      : req.requestBody.toString();
    String signature = firstHeader(req);
    String secret = webhookSecret();

    if (
      String.isBlank(secret) ||
      !AXF_CLS_PluggyWebhookSignature.isValid(rawBody, signature, secret)
    ) {
      res.statusCode = 401;
      res.responseBody = Blob.valueOf(
        '{"accepted":false,"ref":"' + correlationId + '"}'
      );
      return;
    }

    if (!AXF_CLS_PluggySettings.webhookEnabled()) {
      res.statusCode = 202;
      res.responseBody = Blob.valueOf(
        '{"accepted":true,"queued":false,"ref":"' + correlationId + '"}'
      );
      return;
    }

    String itemId;
    try {
      Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
        rawBody
      );
      itemId = firstNonBlank(
        strval(payload.get('itemId')),
        strval(payload.get('id'))
      );
    } catch (Exception ignored) {
      itemId = null;
    }

    Boolean queued = false;
    if (String.isNotBlank(itemId)) {
      // Only triggers a fetch; the payload itself is discarded. The revalidation runs out
      // of the guest-user context via AXF_TRG_PluggyWebhookEvent.
      Database.SaveResult published = EventBus.publish(
        new AXF_PluggyWebhookEvent__e(
          AXF_PWE_TXT_ObservedItemId__c = itemId,
          AXF_PWE_TXT_CorrelationId__c = correlationId
        )
      );
      queued = published != null && published.isSuccess();
    }

    res.statusCode = 200;
    res.responseBody = Blob.valueOf(
      '{"accepted":true,"queued":' +
        String.valueOf(queued) +
        ',"ref":"' +
        correlationId +
        '"}'
    );
  }

  private static String firstHeader(RestRequest req) {
    if (req.headers == null) {
      return null;
    }
    for (String h : SIGNATURE_HEADERS) {
      if (req.headers.containsKey(h) && String.isNotBlank(req.headers.get(h))) {
        return req.headers.get(h);
      }
    }
    return null;
  }

  @TestVisible
  private static String secretOverrideForTests;

  private static String webhookSecret() {
    if (Test.isRunningTest() && secretOverrideForTests != null) {
      return secretOverrideForTests;
    }
    AXF_PluggyWebhookConfig__mdt cfg = AXF_PluggyWebhookConfig__mdt.getInstance(
      'Default'
    );
    return cfg == null ? null : cfg.AXF_PWC_TXT_Secret__c;
  }

  private static String strval(Object o) {
    return o == null ? null : String.valueOf(o);
  }

  private static String firstNonBlank(String a, String b) {
    return String.isNotBlank(a) ? a : b;
  }
}
