/**
 * @description Authenticated GET against the Pluggy API through the AXF_NC_Pluggy_API
 * Named Credential. Shared by the account, transaction and invoice syncs.
 */
public with sharing class ALT_CLS_PluggyApi {
  private static final String BASE = 'callout:AXF_NC_Pluggy_API';

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

  public static List<Object> results(Map<String, Object> page) {
    List<Object> items = (List<Object>) page.get('results');
    return items == null ? new List<Object>() : items;
  }

  public static Date toDate(Object value) {
    String text = value == null ? null : String.valueOf(value);
    return String.isBlank(text) ? null : Date.valueOf(text.substring(0, 10));
  }
}
