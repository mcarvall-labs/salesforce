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
    String eventType;
    String accountId;
    List<String> transactionIds = new List<String>();
    try {
      Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
        rawBody
      );
      itemId = firstNonBlank(
        strval(payload.get('itemId')),
        strval(payload.get('id'))
      );
      eventType = strval(payload.get('event'));
      if (eventType == 'transactions/deleted') {
        if (String.isBlank(itemId) || itemId.length() > 64)
          throw new AXF_CLS_ReviewQueueException('Invalid deletion item.');
        accountId = strval(payload.get('accountId'));
        Object ids = payload.get('transactionIds');
        if (String.isBlank(accountId) || !(ids instanceof List<Object>))
          throw new AXF_CLS_ReviewQueueException(
            'Invalid deletion identifiers.'
          );
        Set<String> distinctIds = new Set<String>();
        for (Object value : (List<Object>) ids) {
          String identifier = strval(value);
          if (String.isBlank(identifier) || identifier.length() > 255)
            throw new AXF_CLS_ReviewQueueException(
              'Invalid deletion identifier.'
            );
          distinctIds.add(identifier);
        }
        transactionIds.addAll(distinctIds);
        if (
          transactionIds.isEmpty() ||
          transactionIds.size() > 500 ||
          accountId.length() > 255
        )
          throw new AXF_CLS_ReviewQueueException('Invalid deletion batch.');
      }
    } catch (Exception ignored) {
      itemId = null;
      if (eventType == 'transactions/deleted') {
        res.statusCode = 400;
        res.responseBody = Blob.valueOf('{"accepted":false}');
        return;
      }
    }

    Boolean queued = false;
    if (String.isNotBlank(itemId)) {
      // Only triggers a fetch; the payload itself is discarded. The revalidation runs out
      // of the guest-user context via AXF_TRG_PluggyWebhookEvent.
      Database.SaveResult published = EventBus.publish(
        new AXF_PluggyWebhookEvent__e(
          AXF_PWE_TXT_ObservedItemId__c = itemId,
          AXF_PWE_TXT_CorrelationId__c = correlationId,
          AXF_PWE_TXT_EventType__c = eventType == 'transactions/deleted'
            ? eventType
            : null,
          AXF_PWE_TXT_AccountId__c = accountId,
          AXF_PWE_TAL_TransactionIds__c = transactionIds.isEmpty()
            ? null
            : JSON.serialize(transactionIds)
        )
      );
      queued = published != null && published.isSuccess();
    }

    res.statusCode = String.isNotBlank(itemId) && !queued ? 503 : 200;
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
