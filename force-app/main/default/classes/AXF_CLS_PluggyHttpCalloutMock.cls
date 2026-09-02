/**
 * @description Shared HttpCalloutMock for the Pluggy tests. Routes by the endpoint suffix so
 * a single instance can answer /auth, /connectors, /items/<id>, /consents and /accounts
 * (AXF-84). Never carries a real secret.
 */
@IsTest
public class AXF_CLS_PluggyHttpCalloutMock implements HttpCalloutMock {
  public Integer authStatus = 200;
  public String apiKey = 'test-api-key-not-a-real-secret';
  public Integer connectorsStatus = 200;
  public Integer itemStatus = 200;
  public String itemBodyStatus = 'UPDATED';
  public Integer consentsStatus = 200;
  public String consentRevokedAt = null;
  public String consentExpiresAt = null;
  public String consentItemId = 'ITEM_ORIGIN_A';
  public Boolean throwCallout = false;

  // --- /accounts (AXF-84 discovery) ---
  public Integer accountsStatus = 200;
  public Integer accountsTotalPages = 1;
  public String accountsBodyJson; // full override; when null a default 1 bank + 1 card is returned
  public Boolean throwOnAccounts = false;

  public List<String> requestedPaths = new List<String>();

  public HTTPResponse respond(HTTPRequest req) {
    if (throwCallout) {
      throw new System.CalloutException('simulated timeout');
    }
    String ep = req.getEndpoint();
    requestedPaths.add(ep);
    HttpResponse res = new HttpResponse();
    res.setHeader('Content-Type', 'application/json');

    if (ep.endsWith('/auth')) {
      res.setStatusCode(authStatus);
      res.setBody(
        authStatus != 200
          ? '{"message":"client keys are invalid"}'
          : (apiKey == null ? '{}' : '{"apiKey":"' + apiKey + '"}')
      );
      return res;
    }
    if (ep.contains('/connectors')) {
      res.setStatusCode(connectorsStatus);
      res.setBody('{"results":[{"id":201,"name":"Test Bank"}]}');
      return res;
    }
    if (ep.contains('/consents')) {
      res.setStatusCode(consentsStatus);
      if (consentsStatus == 200) {
        res.setBody(
          '{"total":1,"totalPages":1,"page":1,"results":[{' +
            '"id":"CONSENT_A","itemId":"' +
            consentItemId +
            '",' +
            '"products":["ACCOUNTS","CREDIT_CARDS","TRANSACTIONS"],' +
            '"openFinancePermissionsGranted":["ACCOUNTS_ALL"],' +
            '"createdAt":"2026-01-01T00:00:00.000Z",' +
            '"expiresAt":' +
            jsonValue(consentExpiresAt) +
            ',' +
            '"revokedAt":' +
            jsonValue(consentRevokedAt) +
            '}]}'
        );
      } else {
        res.setBody('{"message":"forbidden"}');
      }
      return res;
    }
    if (ep.contains('/accounts')) {
      if (throwOnAccounts) {
        throw new System.CalloutException('simulated accounts timeout');
      }
      res.setStatusCode(accountsStatus);
      if (accountsStatus != 200) {
        res.setBody('{"message":"forbidden"}');
        return res;
      }
      if (accountsBodyJson != null) {
        res.setBody(accountsBodyJson);
        return res;
      }
      res.setBody(
        '{"total":2,"totalPages":' +
          accountsTotalPages +
          ',"page":1,"results":[' +
          '{"id":"ACC-1","type":"BANK","subtype":"CHECKING_ACCOUNT","name":"Conta","number":"12345678","balance":100.55,"currencyCode":"BRL"},' +
          '{"id":"ACC-2","type":"CREDIT","name":"Cartao","number":"9999","balance":-50,"currencyCode":"BRL","creditData":{"brand":"VISA","level":"GOLD","creditLimit":5000,"availableCreditLimit":4950}}' +
          ']}'
      );
      return res;
    }
    if (ep.contains('/items/')) {
      res.setStatusCode(itemStatus);
      if (itemStatus == 200) {
        res.setBody(
          '{"id":"ITEM_OBSERVED_A","status":"' +
            itemBodyStatus +
            '",' +
            '"connector":{"id":201,"name":"Test Bank"}}'
        );
      } else {
        res.setBody('{"message":"item error"}');
      }
      return res;
    }

    res.setStatusCode(404);
    res.setBody('{"message":"unmapped"}');
    return res;
  }

  private static String jsonValue(String v) {
    return v == null ? 'null' : '"' + v + '"';
  }
}
