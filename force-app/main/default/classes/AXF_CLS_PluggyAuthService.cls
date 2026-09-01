/**
 * @description Obtains and caches the Pluggy apiKey server-side. Ported from the legacy
 * develop baseline and regressed for AXF-11 (G4-1 / AC8):
 *  - every System.debug of the request/response/apiKey was removed (they leaked the key);
 *  - the cache TTL is short and configurable (AXF_PluggySettings), never the raw ~2h;
 *  - error messages are sanitized: endpoint + HTTP status + correlation id only;
 *  - the Named Credential is resolved from the active rotation slot, and an explicit
 *    Named Credential can be passed to test a candidate without touching the live cache.
 *
 * Secrets (clientId/clientSecret) live only in AXF_EXC_Pluggy(_Candidate); the apiKey lives
 * only in Platform Cache and in-memory here. Neither is ever returned to a client, written
 * to a record, a log, a URL or an error.
 */
public with sharing class AXF_CLS_PluggyAuthService {
  @TestVisible
  private static final String CACHE_PARTITION = 'local.AXFPluggyCache';
  @TestVisible
  private static final String CACHE_KEY_PRIMARY = 'apiKey_PRIMARY';
  @TestVisible
  private static final String CACHE_KEY_CANDIDATE = 'apiKey_CANDIDATE';

  /** @description apiKey for the currently active credential slot (cached). */
  public static String getValidApiKey() {
    return getValidApiKey(AXF_CLS_PluggySettings.activeNamedCredential());
  }

  /**
   * @description apiKey for a specific Named Credential. Used by rotation to test the
   * candidate slot. The candidate result is cached under its own key so a passing test
   * never overwrites the live apiKey.
   */
  public static String getValidApiKey(String namedCredential) {
    String cacheKey = AXF_CLS_PluggySettings.NC_CANDIDATE.equals(
        namedCredential
      )
      ? CACHE_KEY_CANDIDATE
      : CACHE_KEY_PRIMARY;

    String cached = fromCache(cacheKey);
    if (String.isNotBlank(cached)) {
      return cached;
    }
    String apiKey = requestNewApiKey(namedCredential);
    toCache(cacheKey, apiKey);
    return apiKey;
  }

  /** @description Drops the cached apiKey for both slots (e.g. after a promotion). */
  public static void invalidateCache() {
    try {
      Cache.OrgPartition p = Cache.Org.getPartition(CACHE_PARTITION);
      p.remove(CACHE_KEY_PRIMARY);
      p.remove(CACHE_KEY_CANDIDATE);
    } catch (Cache.Org.OrgCacheException e) {
      // No partition capacity: nothing cached, nothing to drop.
    }
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

  private static String fromCache(String key) {
    try {
      Cache.OrgPartition p = Cache.Org.getPartition(CACHE_PARTITION);
      if (p != null && p.contains(key)) {
        return (String) p.get(key);
      }
    } catch (Cache.Org.OrgCacheException e) {
      // No partition capacity allocated: proceed without cache.
    }
    return null;
  }

  private static void toCache(String key, String apiKey) {
    try {
      Cache.OrgPartition p = Cache.Org.getPartition(CACHE_PARTITION);
      if (p != null) {
        p.put(key, apiKey, AXF_CLS_PluggySettings.apiKeyCacheTtlSeconds());
      }
    } catch (Cache.Org.OrgCacheException e) {
      // No partition capacity allocated: apiKey will be re-fetched next call.
    }
  }
}
