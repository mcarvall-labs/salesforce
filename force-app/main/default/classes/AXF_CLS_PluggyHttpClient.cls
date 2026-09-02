/**
 * @description Thin authenticated JSON client for the Pluggy API. Injects the server-side
 * apiKey into the X-API-KEY header in memory (never logged, never returned), attaches a
 * correlation id, and turns every failure into a sanitized message that names only the
 * endpoint, HTTP status and correlation id.
 *
 * Read-only helper for AXF-11 (consent refresh, connectivity test). Sync/retry/cursor logic
 * belongs to AXF-12 — this client does no blind retries and treats timeout as unknown.
 */
public with sharing class AXF_CLS_PluggyHttpClient {
  private final String namedCredential;

  public AXF_CLS_PluggyHttpClient() {
    this(AXF_CLS_PluggySettings.activeNamedCredential());
  }

  public AXF_CLS_PluggyHttpClient(String namedCredentialName) {
    this.namedCredential = namedCredentialName;
  }

  public class PluggyResponse {
    public Integer statusCode;
    public Map<String, Object> body;
    public String correlationId;
    public Boolean isSuccess {
      get {
        return statusCode != null && statusCode >= 200 && statusCode < 300;
      }
    }
  }

  /**
   * @description GET a JSON resource. `path` is a fixed, code-controlled path such as
   * '/items/abc' or '/consents?itemId=abc' — never a client-supplied URL or body.
   */
  public PluggyResponse getJson(String path) {
    String correlationId = newCorrelationId();

    HttpResponse res;
    try {
      String apiKey = AXF_CLS_PluggyAuthService.getValidApiKey(namedCredential);

      HttpRequest req = new HttpRequest();
      req.setEndpoint('callout:' + namedCredential + path);
      req.setMethod('GET');
      req.setHeader('X-API-KEY', apiKey);
      req.setHeader('Accept', 'application/json');
      req.setHeader('X-Request-Id', correlationId);
      req.setTimeout(120000);

      res = new Http().send(req);
    } catch (AXF_CLS_PluggyIntegrationException known) {
      throw known;
    } catch (Exception ce) {
      // Timeout / transport failure: unknown result, never success. No blind retry here.
      throw new AXF_CLS_PluggyIntegrationException(
        sanitizedError(
          'GET ' + publicPath(path) + ' (resultado desconhecido)',
          null,
          correlationId
        )
      );
    }

    PluggyResponse out = new PluggyResponse();
    out.statusCode = res.getStatusCode();
    out.correlationId = correlationId;
    if (out.isSuccess && String.isNotBlank(res.getBody())) {
      try {
        Object parsed = JSON.deserializeUntyped(res.getBody());
        if (parsed instanceof Map<String, Object>) {
          out.body = (Map<String, Object>) parsed;
        }
      } catch (Exception ignored) {
        out.body = null;
      }
    }
    return out;
  }

  public static String newCorrelationId() {
    Blob b = Crypto.generateAesKey(128);
    return EncodingUtil.convertToHex(b).substring(0, 16);
  }

  /**
   * @description Builds a message that is safe to surface to a user or store on a record:
   * no credential, token, request body or raw response body.
   */
  public static String sanitizedError(
    String operation,
    Integer statusCode,
    String correlationId
  ) {
    String status = (statusCode == null)
      ? 'sem resposta'
      : 'HTTP ' + statusCode;
    return 'Falha na integracao Pluggy (' +
      operation +
      ', ' +
      status +
      ', ref ' +
      correlationId +
      '). Nenhum dado sensivel e registrado.';
  }

  private static String publicPath(String path) {
    // Only the resource type reaches user-facing text; ids and query stay internal.
    String p = path.startsWith('/') ? path.substring(1) : path;
    Integer cut = p.length();
    for (String sep : new List<String>{ '/', '?', '&' }) {
      Integer i = p.indexOf(sep);
      if (i >= 0 && i < cut) {
        cut = i;
      }
    }
    return '/' + p.substring(0, cut);
  }
}
