/**
 * @description Serviço responsável por consultar o saldo atual de uma conta na Pluggy (GET /accounts/{id}).
 * A Pluggy API não expõe um sub-endpoint dedicado '/accounts/{id}/balance' — o saldo faz parte do
 * próprio objeto de conta retornado por /accounts/{id}, mesmo payload já consumido em
 * AXF_CLS_PluggyAccountSync_Service para a listagem de contas.
 */
public with sharing class AXF_CLS_PluggyBalanceSync_Service {
  private static final String ACCOUNT_ENDPOINT = 'callout:AXF_NC_Pluggy_API/accounts/';

  public class BalanceResult {
    public Decimal balance;
    public String currencyCode;
    public Datetime lastSync;
  }

  /**
   * @description Busca o saldo atual da conta informada diretamente na Pluggy.
   * @param pluggyAccountId Id da conta na Pluggy (AXF_BA_EXI_PluggyAccountId__c).
   * @param apiKey API Key válida da Pluggy (AXF_CLS_PluggyAuthService.getValidApiKey()).
   * @throws AXF_CLS_PluggyBalanceSync_Service.BalanceSyncException quando a Pluggy retorna um status diferente de 200.
   */
  public static BalanceResult fetchBalance(
    String pluggyAccountId,
    String apiKey
  ) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(
      ACCOUNT_ENDPOINT + EncodingUtil.urlEncode(pluggyAccountId, 'UTF-8')
    );
    req.setMethod('GET');
    req.setHeader('X-API-KEY', apiKey);

    HttpResponse res = new Http().send(req);

    if (res.getStatusCode() != 200) {
      throw new BalanceSyncException(
        'Falha ao consultar saldo na Pluggy (HTTP ' + res.getStatusCode() + ').'
      );
    }

    Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(
      res.getBody()
    );

    BalanceResult result = new BalanceResult();
    result.balance = data.get('balance') != null
      ? (Decimal) data.get('balance')
      : null;
    result.currencyCode = (String) data.get('currency');
    result.lastSync = parseDatetime((String) data.get('updatedAt'));

    return result;
  }

  public class BalanceSyncException extends Exception {
  }

  private static Datetime parseDatetime(String isoDatetime) {
    if (String.isBlank(isoDatetime)) {
      return null;
    }
    return (Datetime) JSON.deserialize('"' + isoDatetime + '"', Datetime.class);
  }
}
