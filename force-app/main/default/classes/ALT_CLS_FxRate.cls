/**
 * @description Keeps the native exchange rate of each foreign currency up to date from the PTAX
 * quote of the Banco Central (buy quote, "Fechamento PTAX" bulletin; public API, no key).
 * Effective rate = quote x (1 - spread) x (1 - IOF), with the spread and the IOF of the currency
 * in AXF_FxParameter__mdt (BRL per foreign unit). The native rate is stored the other way round
 * (foreign units per BRL), so it is 1 / effective rate. On any failure (service down, no bulletin,
 * invalid quote, write refused) the previous rate is left untouched.
 */
public with sharing class ALT_CLS_FxRate {
  public static final String QUOTE_ENDPOINT = 'callout:AXF_NC_BCB_PTAX';
  public static final String CLOSING_BULLETIN = 'Fechamento';
  // BCB publishes no bulletin on weekends and holidays: look back this many days for the last one.
  public static final Integer LOOKBACK_DAYS = 6;

  public class FxException extends Exception {
  }

  // Writes the native rate. The default writes through the REST API of this org, the only way to
  // update CurrencyType (Apex DML is not allowed on it).
  public interface RateWriter {
    void write(String isoCode, Decimal nativeRate);
  }

  public class Outcome {
    public String isoCode;
    public Decimal quote;
    public Decimal effectiveRate;
    public Decimal nativeRate;
    public String error;
  }

  @TestVisible
  private RateWriter writer = new ALT_CLS_FxRateRestWriter();
  @TestVisible
  private Date today = Date.today();
  // Test seam: custom metadata records are not visible to a validation-only deploy.
  @TestVisible
  private List<AXF_FxParameter__mdt> parameterRecords;

  // Effective BRL per foreign unit.
  public static Decimal effectiveRate(
    Decimal quote,
    Decimal spreadPercent,
    Decimal iofPercent
  ) {
    Decimal spread = (spreadPercent == null ? 0 : spreadPercent) / 100;
    Decimal iof = (iofPercent == null ? 0 : iofPercent) / 100;
    return (quote * (1 - spread) * (1 - iof)).setScale(6, RoundingMode.HALF_UP);
  }

  // Native rate = foreign units per BRL.
  public static Decimal nativeRate(Decimal effective) {
    return (Decimal.valueOf(1).divide(effective, 8))
      .setScale(6, RoundingMode.HALF_UP);
  }

  public List<Outcome> updateAll() {
    Map<String, AXF_FxParameter__mdt> parameters = new Map<String, AXF_FxParameter__mdt>();
    List<AXF_FxParameter__mdt> records = parameterRecords != null
      ? parameterRecords
      : [
          SELECT
            AXF_FXP_TXT_CurrencyCode__c,
            AXF_FXP_PCT_Spread__c,
            AXF_FXP_PCT_Iof__c
          FROM AXF_FxParameter__mdt
        ];
    for (AXF_FxParameter__mdt p : records) {
      parameters.put(p.AXF_FXP_TXT_CurrencyCode__c, p);
    }
    List<Outcome> outcomes = new List<Outcome>();
    for (CurrencyType currencyType : [
      SELECT IsoCode
      FROM CurrencyType
      WHERE IsActive = TRUE AND IsCorporate = FALSE
    ]) {
      AXF_FxParameter__mdt parameter = parameters.get(currencyType.IsoCode);
      if (parameter == null) {
        continue;
      }
      outcomes.add(updateOne(currencyType.IsoCode, parameter));
    }
    return outcomes;
  }

  private Outcome updateOne(String isoCode, AXF_FxParameter__mdt parameter) {
    Outcome outcome = new Outcome();
    outcome.isoCode = isoCode;
    try {
      outcome.quote = closingQuote(isoCode);
      outcome.effectiveRate = effectiveRate(
        outcome.quote,
        parameter.AXF_FXP_PCT_Spread__c,
        parameter.AXF_FXP_PCT_Iof__c
      );
      if (outcome.effectiveRate <= 0) {
        throw new FxException(
          'A taxa efetiva de ' + isoCode + ' ficou zerada.'
        );
      }
      outcome.nativeRate = nativeRate(outcome.effectiveRate);
      writer.write(isoCode, outcome.nativeRate);
    } catch (Exception e) {
      outcome.error = e.getMessage();
    }
    return outcome;
  }

  // Buy quote of the last "Fechamento PTAX" bulletin, looking back over weekends and holidays.
  @TestVisible
  private Decimal closingQuote(String isoCode) {
    for (Integer back = 0; back < LOOKBACK_DAYS; back++) {
      Date day = today.addDays(-back);
      String url =
        QUOTE_ENDPOINT +
        '/olinda/servico/PTAX/versao/v1/odata/CotacaoMoedaDia(moeda=@moeda,dataCotacao=@dataCotacao)' +
        '?@moeda=\'' +
        isoCode +
        '\'&@dataCotacao=\'' +
        quoteDate(day) +
        '\'' +
        '&$format=json&$select=cotacaoCompra,tipoBoletim';
      HttpRequest request = new HttpRequest();
      request.setEndpoint(url);
      request.setMethod('GET');
      request.setTimeout(30000);
      HttpResponse response;
      try {
        response = new Http().send(request);
      } catch (Exception e) {
        throw new FxException(
          'Não foi possível contatar o Banco Central (' + e.getTypeName() + ').'
        );
      }
      if (response.getStatusCode() != 200) {
        throw new FxException(
          'O Banco Central respondeu com erro (HTTP ' +
            response.getStatusCode() +
            ').'
        );
      }
      Decimal quote = closingQuoteOf(response.getBody());
      if (quote != null) {
        return quote;
      }
    }
    throw new FxException(
      'Sem boletim de fechamento do PTAX para ' +
        isoCode +
        ' nos últimos ' +
        LOOKBACK_DAYS +
        ' dias.'
    );
  }

  @TestVisible
  private static Decimal closingQuoteOf(String body) {
    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
      body
    );
    List<Object> rows = (List<Object>) parsed.get('value');
    if (rows == null) {
      return null;
    }
    for (Object row : rows) {
      Map<String, Object> item = (Map<String, Object>) row;
      String bulletin = (String) item.get('tipoBoletim');
      if (bulletin != null && bulletin.startsWith(CLOSING_BULLETIN)) {
        Object value = item.get('cotacaoCompra');
        if (value == null) {
          return null;
        }
        Decimal quote = Decimal.valueOf(String.valueOf(value));
        if (quote <= 0) {
          throw new FxException('Cotação inválida recebida do Banco Central.');
        }
        return quote;
      }
    }
    return null;
  }

  // The BCB service takes the day as MM-DD-YYYY.
  @TestVisible
  private static String quoteDate(Date day) {
    return String.valueOf(day.month()).leftPad(2, '0') +
      '-' +
      String.valueOf(day.day()).leftPad(2, '0') +
      '-' +
      day.year();
  }
}
