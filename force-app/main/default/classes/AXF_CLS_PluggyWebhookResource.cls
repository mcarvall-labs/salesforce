/**
 * @description Inbound Pluggy webhook endpoint. Fechamento G4-3:
 *   - a shared secret carried in a request header is verified BEFORE anything is accepted.
 *     Pluggy does not sign its webhooks (no HMAC); it forwards the custom headers you
 *     register with the webhook, so the shared secret is registered there and matched here
 *     against the protected CMT AXF_PluggyWebhookConfig__mdt (constant-time);
 *   - a missing/wrong secret returns 401 and nothing is processed or logged (only status +
 *     correlation id);
 *   - a valid payload ONLY publishes AXF_PluggyWebhookEvent__e (handled out of the guest
 *     context by AXF_TRG_PluggyWebhookEvent); the payload is never written as a fact.
 *
 * This runs as the Site guest user, whose license forbids writing to
 * AXF_OBJ_PluggyConnection__c and using the External Credential — so the guest only
 * verifies + publishes, and AXF_CLS_PluggyWebhookEventHandler does the callout + write.
 *
 * Exposing this at a public URL (Site + guest user) and registering the header on the
 * Pluggy webhook are manual install steps (AXF-77). The class, the verification and the
 * tests are the deliverable.
 */
@RestResource(urlMapping='/pluggy/webhook')
global with sharing class AXF_CLS_PluggyWebhookResource {
  // Header names accepted for the shared secret. Register one of these on the Pluggy
  // webhook's `headers` object; "X-Webhook-Token" is the documented default.
  @TestVisible
  private static final List<String> AUTH_HEADERS = new List<String>{
    'X-Webhook-Token',
    'X-Webhook-Secret',
    'Authorization'
  };

  @TestVisible
  private static String secretOverrideForTests;

  /** Processes an authenticated Pluggy webhook notification. */
  @HttpPost
  global static void handlePost() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    String correlationId = AXF_CLS_PluggyHttpClient.newCorrelationId();
    res.addHeader('X-Request-Id', correlationId);

    String rawBody = (req.requestBody == null)
      ? null
      : req.requestBody.toString();
    String presented = presentedSecret(req);
    String secret = webhookSecret();

    if (!AXF_CLS_PluggyWebhookAuth.isAuthorized(presented, secret)) {
      res.statusCode = 401;
      res.responseBody = Blob.valueOf(
        '{"accepted":false,"ref":"' + correlationId + '"}'
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

  private static String presentedSecret(RestRequest req) {
    if (req.headers == null) {
      return null;
    }
    for (String h : AUTH_HEADERS) {
      if (req.headers.containsKey(h) && String.isNotBlank(req.headers.get(h))) {
        return req.headers.get(h);
      }
    }
    return null;
  }

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
