/**
 * @description Obtains the Pluggy apiKey server-side. Ported from the legacy develop
 * baseline and regressed for AXF-11 (G4-1 / AC8):
 *  - every System.debug of the request/response/apiKey was removed (they leaked the key);
 *  - no persistent cache: the apiKey is held only for the current Apex transaction
 *    (one POST /auth per transaction, as the G4 investigation recommended);
 *  - error messages are sanitized: endpoint + HTTP status + correlation id only;
 *  - the Named Credential is resolved from the active rotation slot, and an explicit
 *    Named Credential can be passed to test a candidate without touching the live key.
 *
 * Secrets (clientId/clientSecret) live only in AXF_EXC_Pluggy(_Candidate); the apiKey lives
 * only in the in-memory map below for the duration of one request. Neither is ever returned
 * to a client, written to a record, a log, a URL or an error.
 */
public with sharing class AXF_CLS_PluggyAuthService {
  private static final Map<String, String> APIKEY_BY_NC = new Map<String, String>();

  /** @description apiKey for the currently active credential slot. */
  public static String getValidApiKey() {
    return getValidApiKey(AXF_CLS_PluggySettings.activeNamedCredential());
  }

  /**
   * @description apiKey for a specific Named Credential. Used by rotation to test the
   * candidate slot without disturbing the live key.
   */
  public static String getValidApiKey(String namedCredential) {
    String cached = APIKEY_BY_NC.get(namedCredential);
    if (String.isNotBlank(cached)) {
      return cached;
    }
    String apiKey = requestNewApiKey(namedCredential);
    APIKEY_BY_NC.put(namedCredential, apiKey);
    return apiKey;
  }

  /** @description Forgets the current-transaction apiKey (e.g. after a promotion). */
  public static void invalidateCache() {
    APIKEY_BY_NC.clear();
  }

  private static String requestNewApiKey(String namedCredential) {
    String correlationId = AXF_CLS_PluggyHttpClient.newCorrelationId();

    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:' + namedCredential + '/auth');
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setHeader('X-Request-Id', correlationId);
    // Merge fields are resolved by the platform after send; the literal placeholder text
    // below is what req.getBody() returns, so it is safe even if inspected.
    req.setBody(
      '{"clientId":"{!$Credential.' +
        externalCredentialFor(namedCredential) +
        '.clientId}","clientSecret":"{!$Credential.' +
        externalCredentialFor(namedCredential) +
        '.clientSecret}"}'
    );
    req.setTimeout(120000);

    HttpResponse res = new Http().send(req);

    if (res.getStatusCode() != 200) {
      throw new AXF_CLS_PluggyAuthException(
        AXF_CLS_PluggyHttpClient.sanitizedError(
          'POST /auth',
          res.getStatusCode(),
          correlationId
        )
      );
    }

    String apiKey;
    try {
      Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
        res.getBody()
      );
      apiKey = (String) body.get('apiKey');
    } catch (Exception parseError) {
      throw new AXF_CLS_PluggyAuthException(
        AXF_CLS_PluggyHttpClient.sanitizedError(
          'POST /auth (resposta ilegivel)',
          res.getStatusCode(),
          correlationId
        )
      );
    }

    if (String.isBlank(apiKey)) {
      throw new AXF_CLS_PluggyAuthException(
        AXF_CLS_PluggyHttpClient.sanitizedError(
          'POST /auth (apiKey ausente)',
          res.getStatusCode(),
          correlationId
        )
      );
    }
    return apiKey;
  }

  private static String externalCredentialFor(String namedCredential) {
    return AXF_CLS_PluggySettings.NC_CANDIDATE.equals(namedCredential)
      ? 'AXF_EXC_Pluggy_Candidate'
      : 'AXF_EXC_Pluggy';
  }
}
