/**
 * @description Authenticated GET against the Pluggy API through the AXF_NC_Pluggy_API
 * Named Credential. Shared by the account, transaction and invoice syncs.
 */
public with sharing class ALT_CLS_PluggyApi {
  private static final String BASE = 'callout:AXF_NC_Pluggy_API';
  @TestVisible
  private static Integer maxPages = 20;

  private String apiKey;

  public Map<String, Object> get(String pathAndQuery) {
    if (apiKey == null) {
      apiKey = new ALT_CLS_PluggyCredential().requestApiKey();
    }
    HttpRequest req = new HttpRequest();
    req.setEndpoint(BASE + pathAndQuery);
    req.setMethod('GET');
    req.setHeader('X-API-KEY', apiKey);
    HttpResponse res;
    try {
      res = new Http().send(req);
    } catch (Exception e) {
      throw new ALT_CLS_PluggyCredential.PluggyException(
        'Não foi possível contatar o Pluggy (' + e.getTypeName() + ').'
      );
    }
    if (res.getStatusCode() != 200) {
      throw new ALT_CLS_PluggyCredential.PluggyException(
        'O Pluggy respondeu com erro (HTTP ' + res.getStatusCode() + ').'
      );
    }
    return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
  }

  // Follows the cursor of the v2 endpoints ({results, next}). Reaching the page ceiling with a
  // cursor still pending fails instead of returning a partial list: a silent cut would be
  // skipped forever by the incremental window of the next run.
  public List<Object> getAll(String pathAndQuery) {
    List<Object> all = new List<Object>();
    String cursor;
    for (Integer page = 0; page < maxPages; page++) {
      Map<String, Object> body = get(
        cursor == null
          ? pathAndQuery
          : pathAndQuery +
            (pathAndQuery.contains('?') ? '&' : '?') +
            'after=' +
            EncodingUtil.urlEncode(cursor, 'UTF-8')
      );
      all.addAll(results(body));
      cursor = (String) body.get('next');
      if (String.isBlank(cursor)) {
        return all;
      }
    }
    throw new ALT_CLS_PluggyCredential.PluggyException(
      'O Pluggy retornou mais de ' +
        maxPages +
        ' páginas; nada foi gravado para não perder histórico. Reduza a janela ou aumente o limite.'
    );
  }

  public static List<Object> results(Map<String, Object> page) {
    List<Object> items = (List<Object>) page.get('results');
    return items == null ? new List<Object>() : items;
  }

  public static Date toDate(Object value) {
    String text = value == null ? null : String.valueOf(value);
    return String.isBlank(text) ? null : Date.valueOf(text.substring(0, 10));
  }
}
