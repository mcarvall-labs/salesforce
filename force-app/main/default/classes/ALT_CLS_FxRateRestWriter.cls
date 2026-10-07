/**
 * @description Writes the native rate of a currency with the REST API of this org (PATCH on
 * CurrencyType), through the Named Credential AXF_NC_Salesforce_Rest, because Apex DML is not
 * allowed on CurrencyType. The Named Credential is a manual setup step (see docs/MANUAL_STEPS.md).
 */
public with sharing class ALT_CLS_FxRateRestWriter implements ALT_CLS_FxRate.RateWriter {
  public static final String ENDPOINT = 'callout:AXF_NC_Salesforce_Rest';
  public static final String API_VERSION = 'v62.0';

  public void write(String isoCode, Decimal nativeRate) {
    List<CurrencyType> found = [
      SELECT Id
      FROM CurrencyType
      WHERE IsoCode = :isoCode
      LIMIT 1
    ];
    if (found.isEmpty()) {
      throw new ALT_CLS_FxRate.FxException(
        'A moeda ' + isoCode + ' não existe nesta org.'
      );
    }
    HttpRequest request = new HttpRequest();
    request.setEndpoint(
      ENDPOINT +
        '/services/data/' +
        API_VERSION +
        '/sobjects/CurrencyType/' +
        found[0].Id
    );
    request.setMethod('PATCH');
    request.setHeader('Content-Type', 'application/json');
    request.setBody(
      JSON.serialize(new Map<String, Object>{ 'ConversionRate' => nativeRate })
    );
    request.setTimeout(30000);
    HttpResponse response;
    try {
      response = new Http().send(request);
    } catch (Exception e) {
      throw new ALT_CLS_FxRate.FxException(
        'Não foi possível gravar a taxa de ' +
          isoCode +
          ' (' +
          e.getTypeName() +
          ').'
      );
    }
    if (response.getStatusCode() != 204) {
      throw new ALT_CLS_FxRate.FxException(
        'A org recusou a taxa de ' +
          isoCode +
          ' (HTTP ' +
          response.getStatusCode() +
          ').'
      );
    }
  }
}
