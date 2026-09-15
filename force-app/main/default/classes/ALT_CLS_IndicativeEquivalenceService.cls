/**
 * @description Equivalencia monetaria INDICATIVA de exibicao (AXF-92, G8 fechado 30/08).
 *
 * Camada de apresentacao leve e recomputavel ao lado do valor original: mostra a moeda original
 * e, quando ha cotacao indicativa valida, uma equivalencia rotulada como estimativa com fonte,
 * data e estado. Regras (G8-2/G8-3/G8-4):
 * - Nunca altera CurrencyIsoCode, saldo, historico ou taxa praticada; nao cria snapshot nem DML;
 * - Nunca inventa taxa, paridade, provider ou atualizacao; sem cotacao valida -> UNAVAILABLE e o
 *   numero e omitido (a decisao continua sobre o valor original);
 * - Cotacao com mais de 7 dias -> STALE (numero omitido), sem assumir paridade;
 * - Mesma moeda -> SAME_CURRENCY (somente original);
 * - Usuario sem acesso ao saldo/registro -> negado tambem a equivalencia, sem vazar existencia;
 * - Arredondamento HALF_UP aplicado somente no valor exibido (escala ISO da moeda de reporte).
 * A conversao efetiva de dinheiro pertence a AXF-59..63; esta camada nao a executa.
 */
public with sharing class ALT_CLS_IndicativeEquivalenceService {
  public static final String STATE_SAME_CURRENCY = 'SAME_CURRENCY';
  public static final String STATE_ESTIMATED = 'ESTIMATED';
  public static final String STATE_STALE = 'STALE';
  public static final String STATE_UNAVAILABLE = 'UNAVAILABLE';

  public static final String PROVIDER_BCB_PTAX = 'BCB_PTAX';
  public static final Integer QUOTE_MAX_AGE_DAYS = 7;
  public static final Integer DISPLAY_SCALE = 2;

  /** Resultado da equivalencia indicativa para um valor original. */
  public class EquivalenceViewDTO {
    @AuraEnabled
    public Boolean accessible;
    @AuraEnabled
    public Boolean originalOnly;
    @AuraEnabled
    public String state; // SAME_CURRENCY | ESTIMATED | STALE | UNAVAILABLE
    @AuraEnabled
    public Decimal originalAmount;
    @AuraEnabled
    public String originalIso;
    @AuraEnabled
    public Decimal reportingAmount; // preenchido somente em ESTIMATED
    @AuraEnabled
    public String reportingIso;
    @AuraEnabled
    public Decimal rate;
    @AuraEnabled
    public String provider;
    @AuraEnabled
    public Datetime effectiveAt;
    @AuraEnabled
    public String label; // rotulo acessivel da equivalencia
    @AuraEnabled
    public String message;
  }

  /**
   * Calcula a equivalencia indicativa para um valor de um registro que o usuario pode ler.
   * @param contextRecordId Account ou FinancialTransaction raiz do saldo (gate de acesso).
   * @param originalAmount magnitude original (nunca alterada).
   * @param originalIso moeda original (ISO 4217).
   * @param reportingIsoOverride moeda de apresentacao (default: preferencia efetiva AXF-87).
   */
  public EquivalenceViewDTO compute(
    Id contextRecordId,
    Decimal originalAmount,
    String originalIso,
    String reportingIsoOverride
  ) {
    validate(originalAmount, originalIso);

    EquivalenceViewDTO out = new EquivalenceViewDTO();
    out.originalAmount = originalAmount;
    out.originalIso = normalize(originalIso);
    out.accessible = canReadContext(contextRecordId);
    if (out.accessible != true) {
      out.originalOnly = true;
      out.state = STATE_UNAVAILABLE;
      out.message = 'Sem acesso ao saldo: a equivalencia nao pode ser apresentada.';
      return out;
    }

    String reportingIso = normalize(
      String.isBlank(reportingIsoOverride)
        ? new AXF_CLS_ReportCurrencyService().effectivePreference()
        : reportingIsoOverride
    );
    if (String.isBlank(reportingIso)) {
      out.originalOnly = true;
      out.state = STATE_UNAVAILABLE;
      out.message = 'Moeda de apresentacao nao definida; somente o valor original e exibido.';
      return out;
    }
    out.reportingIso = reportingIso;

    if (out.originalIso.equalsIgnoreCase(reportingIso)) {
      out.originalOnly = true;
      out.state = STATE_SAME_CURRENCY;
      out.label = 'Mesma moeda: sem equivalencia estimada.';
      return out;
    }

    AXF_OBJ_ExchangeRate__c quote = latestQuote(
      out.originalIso,
      reportingIso,
      System.now()
    );
    if (quote == null) {
      out.originalOnly = true;
      out.state = STATE_UNAVAILABLE;
      out.message =
        'Cotacao indicativa indisponivel para ' +
        out.originalIso +
        '/' +
        reportingIso +
        '; somente o valor original e exibido (sem inventar taxa).';
      return out;
    }

    out.rate = quote.AXF_EXR_NUM_Rate__c;
    out.provider = quote.AXF_EXR_TXT_Provider__c;
    out.effectiveAt = quote.AXF_EXR_DT_EffectiveDateTime__c;
    if (isStale(quote.AXF_EXR_DT_EffectiveDateTime__c)) {
      out.originalOnly = true;
      out.state = STATE_STALE;
      out.message =
        'Cotacao com mais de ' +
        QUOTE_MAX_AGE_DAYS +
        ' dias (' +
        String.valueOf(out.effectiveAt) +
        '): equivalencia omitida, sem assumir paridade.';
      return out;
    }

    Decimal raw = originalAmount * quote.AXF_EXR_NUM_Rate__c;
    out.reportingAmount = raw.setScale(
      DISPLAY_SCALE,
      System.RoundingMode.HALF_UP
    );
    out.originalOnly = false;
    out.state = STATE_ESTIMATED;
    out.label =
      'Equivalencia estimada em ' +
      reportingIso +
      ' - ' +
      out.provider +
      ' em ' +
      String.valueOf(out.effectiveAt);
    return out;
  }

  public EquivalenceViewDTO computeForUserPreference(
    Id contextRecordId,
    Decimal originalAmount,
    String originalIso
  ) {
    return compute(contextRecordId, originalAmount, originalIso, null);
  }

  // ---- Internals -------------------------------------------------------------

  private void validate(Decimal originalAmount, String originalIso) {
    if (originalAmount == null || originalIso == null) {
      throw new AXF_CLS_IndicativeEquivalenceException(
        'Valor original e moeda original sao obrigatorios.'
      );
    }
    if (String.isBlank(normalize(originalIso))) {
      throw new AXF_CLS_IndicativeEquivalenceException(
        'Moeda original invalida (ISO 4217).'
      );
    }
  }

  /** Gate de acesso: com sharing, registros invisiveis nao existem para o usuario (sem vazar). */
  private Boolean canReadContext(Id contextRecordId) {
    if (contextRecordId == null) {
      return false;
    }
    Schema.SObjectType t = contextRecordId.getSObjectType();
    if (t == Account.SObjectType) {
      List<Account> rows = [
        SELECT Id
        FROM Account
        WHERE Id = :contextRecordId
        LIMIT 1
      ];
      return !rows.isEmpty();
    }
    if (t == AXF_OBJ_FinancialTransaction__c.SObjectType) {
      List<AXF_OBJ_FinancialTransaction__c> rows = [
        SELECT Id
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id = :contextRecordId
        LIMIT 1
      ];
      return !rows.isEmpty();
    }
    return false;
  }

  private AXF_OBJ_ExchangeRate__c latestQuote(
    String baseIso,
    String quoteIso,
    Datetime now
  ) {
    Datetime oldest = now.addDays(-QUOTE_MAX_AGE_DAYS * 2); // descobre tambem STALE alem da janela
    List<AXF_OBJ_ExchangeRate__c> rates = [
      SELECT
        Id,
        AXF_EXR_NUM_Rate__c,
        AXF_EXR_DT_EffectiveDateTime__c,
        AXF_EXR_TXT_Provider__c
      FROM AXF_OBJ_ExchangeRate__c
      WHERE
        AXF_EXR_TXT_BaseCurrency__c = :baseIso
        AND AXF_EXR_TXT_QuoteCurrency__c = :quoteIso
        AND AXF_EXR_TXT_Provider__c = :PROVIDER_BCB_PTAX
        AND AXF_EXR_DT_EffectiveDateTime__c >= :oldest
      ORDER BY AXF_EXR_DT_EffectiveDateTime__c DESC
      LIMIT 1
    ];
    return rates.isEmpty() ? null : rates[0];
  }

  private Boolean isStale(Datetime effectiveAt) {
    return effectiveAt == null ||
      effectiveAt < System.now().addDays(-QUOTE_MAX_AGE_DAYS);
  }

  private String normalize(String iso) {
    return iso == null ? null : iso.trim().toUpperCase();
  }
}
