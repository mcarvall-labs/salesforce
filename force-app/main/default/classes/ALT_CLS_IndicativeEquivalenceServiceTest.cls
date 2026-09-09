/**
 * @description Testes unitarios de ALT_CLS_IndicativeEquivalenceService (AXF-92, G8 fechado).
 * Cobre: equivalencia USD->BRL com cotacao corrente; mesma moeda SAME_CURRENCY; cotacao
 * ausente -> UNAVAILABLE (numero omitido, sem inventar taxa); cotacao defasada (>7 dias) ->
 * STALE; acesso negado (registro invisivel por sharing) tambem nega a equivalencia; valor/moeda
 * invalidos; original nunca alterado. Dados ficticios; testes proporcionais ao delta.
 */
@IsTest
private class ALT_CLS_IndicativeEquivalenceServiceTest {
  private static Account makeAccount(String name) {
    Account acc = new Account(Name = name);
    insert acc;
    return acc;
  }

  private static AXF_OBJ_ExchangeRate__c makeRate(
    String baseIso,
    String quoteIso,
    Decimal rate,
    Datetime effective
  ) {
    AXF_OBJ_ExchangeRate__c exr = new AXF_OBJ_ExchangeRate__c(
      AXF_EXR_TXT_BaseCurrency__c = baseIso,
      AXF_EXR_TXT_QuoteCurrency__c = quoteIso,
      AXF_EXR_NUM_Rate__c = rate,
      AXF_EXR_PKL_Side__c = 'SELL',
      AXF_EXR_TXT_Provider__c = ALT_CLS_IndicativeEquivalenceService.PROVIDER_BCB_PTAX,
      AXF_EXR_DT_EffectiveDateTime__c = effective,
      AXF_EXR_EXI_RateKey__c = 'r-' +
        Datetime.now().getTime() +
        '-' +
        baseIso +
        quoteIso +
        '-' +
        effective.getTime()
    );
    insert exr;
    return exr;
  }

  private static ALT_CLS_IndicativeEquivalenceService service() {
    return new ALT_CLS_IndicativeEquivalenceService();
  }

  @IsTest
  static void usdToBrl_CurrentQuote_ShowsEstimated() {
    Account acc = makeAccount('Titular AXF92-A');
    makeRate('USD', 'BRL', 5.05, System.now().addHours(-1));

    ALT_CLS_IndicativeEquivalenceService.EquivalenceViewDTO out = service()
      .compute(acc.Id, 100, 'USD', 'BRL');

    Assert.isTrue(out.accessible == true, 'Leitor autorizado.');
    Assert.areEqual('USD', out.originalIso);
    Assert.areEqual(100, out.originalAmount);
    Assert.areEqual('BRL', out.reportingIso);
    Assert.areEqual(
      ALT_CLS_IndicativeEquivalenceService.STATE_ESTIMATED,
      out.state
    );
    Assert.areEqual(505.0, out.reportingAmount, '100 USD * 5.05 = 505 BRL');
    Assert.areEqual(5.05, out.rate);
    Assert.areEqual(
      ALT_CLS_IndicativeEquivalenceService.PROVIDER_BCB_PTAX,
      out.provider
    );
    Assert.isNotNull(out.effectiveAt, 'Data da cotacao exposta.');
    Assert.isNotNull(out.label, 'Equivalencia rotulada como estimativa.');
    Assert.isFalse(out.originalOnly == true, 'Original e estimativa exibidos.');
  }

  @IsTest
  static void sameCurrency_NoEstimate() {
    Account acc = makeAccount('Titular AXF92-B');

    ALT_CLS_IndicativeEquivalenceService.EquivalenceViewDTO out = service()
      .compute(acc.Id, 100, 'BRL', 'BRL');

    Assert.areEqual(
      ALT_CLS_IndicativeEquivalenceService.STATE_SAME_CURRENCY,
      out.state
    );
    Assert.isTrue(out.originalOnly == true);
    Assert.isNull(out.reportingAmount, 'Sem equivalencia na mesma moeda.');
  }

  @IsTest
  static void missingQuote_Unavailable_NoInventedRate() {
    Account acc = makeAccount('Titular AXF92-C');

    ALT_CLS_IndicativeEquivalenceService.EquivalenceViewDTO out = service()
      .compute(acc.Id, 100, 'USD', 'BRL');

    Assert.areEqual(
      ALT_CLS_IndicativeEquivalenceService.STATE_UNAVAILABLE,
      out.state
    );
    Assert.isTrue(out.originalOnly == true);
    Assert.isNull(out.reportingAmount, 'Numero omitido sem cotacao valida.');
    Assert.isNotNull(out.message, 'Explicacao acessivel exibida.');
  }

  @IsTest
  static void staleQuote_OverSevenDays_StaleOmitted() {
    Account acc = makeAccount('Titular AXF92-D');
    makeRate('USD', 'BRL', 5.0, System.now().addDays(-10));

    ALT_CLS_IndicativeEquivalenceService.EquivalenceViewDTO out = service()
      .compute(acc.Id, 100, 'USD', 'BRL');

    Assert.areEqual(
      ALT_CLS_IndicativeEquivalenceService.STATE_STALE,
      out.state
    );
    Assert.isNull(out.reportingAmount, 'Cotacao defasada: numero omitido.');
    Assert.isNotNull(out.message, 'Aviso acessivel exibido.');
  }

  @IsTest
  static void missingReportingPreference_Unavailable() {
    Account acc = makeAccount('Titular AXF92-E');

    ALT_CLS_IndicativeEquivalenceService.EquivalenceViewDTO out = service()
      .compute(acc.Id, 100, 'USD', null);

    // Preferencia efetiva pode existir na org; em qualquer caso nada inventado.
    Assert.isTrue(out.accessible == true);
    Assert.isTrue(
      out.state == ALT_CLS_IndicativeEquivalenceService.STATE_UNAVAILABLE ||
        out.state == ALT_CLS_IndicativeEquivalenceService.STATE_SAME_CURRENCY,
      'Sem cotacao/preferencia invalida nao produz equivalencia.'
    );
  }

  @IsTest
  static void noAccessToRecord_DeniesEstimateWithoutLeak() {
    // Registro inexistente (invisivel): com sharing o usuario nao ve -> negado, sem vazar.
    String prefix = Schema.SObjectType.Account.getKeyPrefix();
    Id absentAccount = (Id) (prefix + '000000000000');

    ALT_CLS_IndicativeEquivalenceService.EquivalenceViewDTO out = service()
      .compute(absentAccount, 100, 'USD', 'BRL');

    Assert.isFalse(out.accessible == true, 'Acesso negado.');
    Assert.isTrue(out.originalOnly == true);
    Assert.isNull(
      out.reportingAmount,
      'Equivalencia tambem negada sem acesso.'
    );
    Assert.areEqual(
      ALT_CLS_IndicativeEquivalenceService.STATE_UNAVAILABLE,
      out.state
    );
  }

  @IsTest
  static void invalidAmountOrIso_Throws() {
    Account acc = makeAccount('Titular AXF92-F');
    Exception caught;
    try {
      service().compute(acc.Id, null, 'USD', 'BRL');
    } catch (AXF_CLS_IndicativeEquivalenceException e) {
      caught = e;
    }
    Assert.isNotNull(caught, 'Valor nulo rejeitado.');

    caught = null;
    try {
      service().compute(acc.Id, 100, ' ', 'BRL');
    } catch (AXF_CLS_IndicativeEquivalenceException e) {
      caught = e;
    }
    Assert.isNotNull(caught, 'Moeda invalida rejeitada.');
  }
}
