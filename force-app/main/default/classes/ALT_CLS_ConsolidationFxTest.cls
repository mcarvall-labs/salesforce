/**
 * @description AXF-123: a comparacao entre moedas no consolidado usa a politica cambial canonica
 * (sem paridade, sem taxa local, sem escrever nada) e a neutralizacao de contrapartidas internas
 * alcanca somente um rateio CONFIRMADO cujos participantes estejam todos no escopo autorizado.
 * Cada regra tem um metodo proprio, para que uma unica mutacao falsifique uma unica regra.
 */
@IsTest
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class ALT_CLS_ConsolidationFxTest {
  private static final String PROVIDER = ALT_CLS_IndicativeEquivalenceService.PROVIDER_BCB_PTAX;

  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    User manager = new User(
      Alias = 'axf123g',
      Email = 'axf123g@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'User axf123g',
      LanguageLocaleKey = 'pt_BR',
      LocaleSidKey = 'pt_BR',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = profileId,
      Username = 'axf123g.' + System.now().getTime() + '@example.invalid'
    );
    insert manager;
    Id permissionSetId = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'AXF_PS_GestorFinanceiro'
      LIMIT 1
    ]
    .Id;
    insert new PermissionSetAssignment(
      AssigneeId = manager.Id,
      PermissionSetId = permissionSetId
    );
  }

  private static Account holder(String name) {
    Account result = new Account(
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId(),
      Name = name
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_BankAccount__c bank(
    Id holderId,
    String iso,
    String key
  ) {
    AXF_OBJ_BankAccount__c result = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = holderId,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = iso,
      AXF_BA_TXT_InstitutionName__c = 'Banco ' + key,
      AXF_BA_TXT_NumberMasked__c = '****' + key,
      AXF_BA_EXI_ManualKey__c = 'axf123-' + key + '-' + System.now().getTime(),
      AXF_BA_NUM_Version__c = 0
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_BankAccountTransaction__c bat(
    Id bankId,
    String iso,
    Decimal magnitude,
    String direction,
    String key
  ) {
    return new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bankId,
      AXF_BAT_EXI_SourceKey__c = 'axf123-' + key + '-' + System.now().getTime(),
      AXF_BAT_PKL_Source__c = 'MANUAL',
      AXF_BAT_DAT_Date__c = Date.newInstance(2026, 8, 10),
      AXF_BAT_NUM_Magnitude__c = magnitude,
      AXF_BAT_PKL_Direction__c = direction,
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_TXT_CurrencyIsoCode__c = iso,
      AXF_BAT_TXT_Description__c = key,
      AXF_BAT_NUM_Version__c = 0
    );
  }

  /** Reference data is written by the integration principal, never by the business user (AXF-92). */
  private static void quote(
    String baseIso,
    String quoteIso,
    Decimal rate,
    Datetime effectiveAt,
    String side,
    String key,
    String provider
  ) {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new AXF_OBJ_ExchangeRate__c(
        AXF_EXR_TXT_BaseCurrency__c = baseIso,
        AXF_EXR_TXT_QuoteCurrency__c = quoteIso,
        AXF_EXR_NUM_Rate__c = rate,
        AXF_EXR_PKL_Side__c = side,
        AXF_EXR_TXT_Provider__c = provider,
        AXF_EXR_DT_EffectiveDateTime__c = effectiveAt,
        AXF_EXR_EXI_RateKey__c = 'axf123-' + key
      );
    }
  }

  private static void quote(
    String baseIso,
    String quoteIso,
    Decimal rate,
    Datetime effectiveAt,
    String side,
    String key
  ) {
    quote(baseIso, quoteIso, rate, effectiveAt, side, key, PROVIDER);
  }

  /** A 50/50 counter-entry of one fact, written inside the service write window of AXF-126. */
  private static AXF_OBJ_EconomicAllocationSet__c allocation(
    AXF_OBJ_BankAccountTransaction__c fact,
    Id holderId,
    String state,
    List<Id> accountIds
  ) {
    ALT_CLS_EconomicAllocationGuard.beginWrite();
    AXF_OBJ_EconomicAllocationSet__c allocationSet = new AXF_OBJ_EconomicAllocationSet__c(
      AXF_EAS_LKP_BankTransaction__c = fact.Id,
      AXF_EAS_LKP_HolderAccount__c = holderId,
      AXF_EAS_TXT_FactIdentity__c = 'axf123-set-' + fact.Id,
      AXF_EAS_NUM_Revision__c = 1,
      AXF_EAS_NUM_FactMagnitude__c = fact.AXF_BAT_NUM_Magnitude__c,
      AXF_EAS_TXT_CurrencyIsoCode__c = fact.AXF_BAT_TXT_CurrencyIsoCode__c,
      AXF_EAS_EXI_SetKey__c = 'axf123-set-' + fact.Id,
      AXF_EAS_PKL_State__c = 'DRAFT'
    );
    insert allocationSet;
    List<AXF_OBJ_EconomicAllocation__c> parcels = new List<AXF_OBJ_EconomicAllocation__c>();
    // The remainder of an uneven split goes to the last parcel, so the shares always total 100%.
    Decimal percent = (100.0 / accountIds.size()).setScale(2);
    Decimal shared = 0;
    for (Integer i = 0; i < accountIds.size(); i++) {
      Decimal share = i == accountIds.size() - 1 ? 100 - shared : percent;
      shared += share;
      parcels.add(
        new AXF_OBJ_EconomicAllocation__c(
          AXF_EA_MDR_AllocationSet__c = allocationSet.Id,
          AXF_EA_LKP_Account__c = accountIds[i],
          AXF_EA_NUM_Percent__c = share,
          AXF_EA_NUM_Magnitude__c = allocationSet.AXF_EAS_NUM_FactMagnitude__c *
            share /
            100,
          AXF_EA_PKL_RedactionPolicy__c = 'OWN_SHARE_ONLY',
          AXF_EA_TXT_CurrencyIsoCode__c = allocationSet.AXF_EAS_TXT_CurrencyIsoCode__c,
          AXF_EA_EXI_AllocationKey__c = 'axf123-share-' +
            fact.Id +
            '-' +
            accountIds[i]
        )
      );
    }
    insert parcels;
    if (state == 'CONFIRMED') {
      allocationSet.AXF_EAS_PKL_State__c = 'CONFIRMED';
      update allocationSet;
    }
    ALT_CLS_EconomicAllocationGuard.endWrite();
    return allocationSet;
  }

  private static ALT_CLS_ConsolidationService.ScopeInput scope(
    List<Id> ids,
    String reportingIso
  ) {
    ALT_CLS_ConsolidationService.ScopeInput input = new ALT_CLS_ConsolidationService.ScopeInput();
    input.accountIds = ids;
    input.reportingIso = reportingIso;
    return input;
  }

  private static ALT_CLS_ConsolidationService.Contribution contribution(
    ALT_CLS_ConsolidationService.Result result,
    Id accountId,
    Id sourceId
  ) {
    for (ALT_CLS_ConsolidationService.Contribution c : result.contributions) {
      if (c.accountId == accountId && c.sourceId == sourceId) {
        return c;
      }
    }
    return null;
  }

  private static ALT_CLS_ConsolidationService.Total total(
    ALT_CLS_ConsolidationService.Result result,
    String currencyIso
  ) {
    for (ALT_CLS_ConsolidationService.Total t : result.totals) {
      if (t.currencyIso == currencyIso) {
        return t;
      }
    }
    return null;
  }

  // -------------------------------------------------------------- AC-1 (a): neutralization

  /**
   * The calculation is a read: it writes nothing at all, so no property and no economic
   * attribution can move. Every contribution still carries its own holder, its original currency,
   * its effective range and the source it came from.
   */
  @IsTest
  static void calculatingTheViewWritesNothingAndKeepsEveryAttribution() {
    System.runAs(byAlias('axf123g')) {
      Account holderA = holder('Titular A');
      Account holderB = holder('Titular B');
      AXF_OBJ_BankAccount__c bankA = bank(holderA.Id, 'BRL', 'a');
      AXF_OBJ_BankAccountTransaction__c fact = bat(
        bankA.Id,
        'BRL',
        300,
        'DEBIT',
        'hold'
      );
      insert fact;
      AXF_OBJ_EconomicAllocationSet__c confirmed = allocation(
        fact,
        holderA.Id,
        'CONFIRMED',
        new List<Id>{ holderA.Id, holderB.Id }
      );
      String factBefore = JSON.serialize(factRow(fact.Id));
      String setBefore = JSON.serialize(setRow(confirmed.Id));
      String parcelsBefore = JSON.serialize(parcelRows(confirmed.Id));
      Test.startTest();
      Integer dmlBefore = Limits.getDmlStatements();
      ALT_CLS_ConsolidationService.Result result = new ALT_CLS_ConsolidationService()
        .consolidate(scope(new List<Id>{ holderA.Id, holderB.Id }, null));
      Assert.areEqual(
        dmlBefore,
        Limits.getDmlStatements(),
        'a consolidacao nao escreve nada (nem propriedade, nem atribuicao)'
      );
      Test.stopTest();
      Assert.areEqual(
        factBefore,
        JSON.serialize(factRow(fact.Id)),
        'o fato de origem permanece imutavel'
      );
      Assert.areEqual(
        setBefore,
        JSON.serialize(setRow(confirmed.Id)),
        'o conjunto confirmado permanece imutavel'
      );
      Assert.areEqual(
        parcelsBefore,
        JSON.serialize(parcelRows(confirmed.Id)),
        'as parcelas permanecem imutaveis'
      );
      ALT_CLS_ConsolidationService.Contribution holderShare = contribution(
        result,
        holderA.Id,
        bankA.Id
      );
      Assert.areEqual('ALLOCATION', holderShare.attribution);
      Assert.areEqual(
        'BRL',
        holderShare.currencyIso,
        'moeda original preservada'
      );
      Assert.areEqual(150, holderShare.outflow);
      Assert.areEqual('BANK', holderShare.sourceKind);
      Assert.areEqual('Banco a ****a', holderShare.sourceLabel);
      Assert.areEqual(Date.newInstance(2026, 8, 10), holderShare.effectiveFrom);
      ALT_CLS_ConsolidationService.Contribution otherShare = contribution(
        result,
        holderB.Id,
        bankA.Id
      );
      Assert.areEqual('Titular B', otherShare.accountName);
      Assert.areEqual(150, otherShare.outflow);
    }
  }

  /** An internal counter-entry that is not CONFIRMED is not a counter-entry yet: nothing is netted. */
  @IsTest
  static void anUnconfirmedCounterEntryIsNeverNeutralized() {
    System.runAs(byAlias('axf123g')) {
      Account holderA = holder('Titular A');
      Account holderB = holder('Titular B');
      AXF_OBJ_BankAccount__c bankA = bank(holderA.Id, 'BRL', 'a');
      AXF_OBJ_BankAccountTransaction__c fact = bat(
        bankA.Id,
        'BRL',
        300,
        'DEBIT',
        'draft'
      );
      insert fact;
      allocation(
        fact,
        holderA.Id,
        'DRAFT',
        new List<Id>{ holderA.Id, holderB.Id }
      );
      Test.startTest();
      ALT_CLS_ConsolidationService.Result draft = new ALT_CLS_ConsolidationService()
        .consolidate(scope(new List<Id>{ holderA.Id, holderB.Id }, null));
      Test.stopTest();
      Assert.areEqual(
        'HOLDER',
        contribution(draft, holderA.Id, bankA.Id).attribution,
        'rascunho nao neutraliza: o fato fica onde esta'
      );
      Assert.areEqual(300, total(draft, 'BRL').outflow);
      Assert.isNull(
        contribution(draft, holderB.Id, bankA.Id),
        'nenhuma parcela de rascunho entra no total'
      );
    }
  }

  /** The counter-entry is netted only when *every* participant is inside the authorized scope. */
  @IsTest
  static void aCounterEntryOutsideTheAuthorizedScopeIsNeverNeutralized() {
    System.runAs(byAlias('axf123g')) {
      Account holderA = holder('Titular A');
      Account holderB = holder('Titular B');
      AXF_OBJ_BankAccount__c bankA = bank(holderA.Id, 'BRL', 'a');
      AXF_OBJ_BankAccountTransaction__c fact = bat(
        bankA.Id,
        'BRL',
        300,
        'DEBIT',
        'outside'
      );
      insert fact;
      allocation(
        fact,
        holderA.Id,
        'CONFIRMED',
        new List<Id>{ holderA.Id, holderB.Id }
      );
      Test.startTest();
      ALT_CLS_ConsolidationService.Result result = new ALT_CLS_ConsolidationService()
        .consolidate(scope(new List<Id>{ holderA.Id }, null));
      Test.stopTest();
      Assert.areEqual(
        'HOLDER',
        contribution(result, holderA.Id, bankA.Id).attribution,
        'sem o participante no escopo a contrapartida fica pendente'
      );
      Assert.areEqual(300, total(result, 'BRL').outflow);
      Assert.isNull(
        contribution(result, holderB.Id, bankA.Id),
        'o participante fora do escopo nao e nomeado nem somado'
      );
      Assert.isTrue(
        result.reasons.contains('ALLOCATED_OUTSIDE_SCOPE'),
        result.reasons.toString()
      );
      Assert.areEqual(
        ALT_CLS_ConsolidationService.CONFIDENCE_DEGRADED,
        result.confidence
      );
    }
  }

  // -------------------------------------------------------------- AC-2 (b): currency comparison

  /**
   * The comparison converts on the canonical indicative policy: the ratified provider, the BUY
   * quote for the asset inflow and the SELL quote for the expense outflow, displayed rounding, and
   * no original value touched. Parity (1:1), a single rate for both sides and truncation each give
   * a different number here.
   */
  @IsTest
  static void theComparisonUsesTheCanonicalQuoteAndMovesNoOriginal() {
    System.runAs(byAlias('axf123g')) {
      Account holderA = holder('Titular A');
      Account holderB = holder('Titular B');
      AXF_OBJ_BankAccount__c bankBrlA = bank(holderA.Id, 'BRL', 'a');
      AXF_OBJ_BankAccount__c bankUsdA = bank(holderA.Id, 'USD', 'u');
      AXF_OBJ_BankAccount__c bankBrlB = bank(holderB.Id, 'BRL', 'b');
      insert new List<AXF_OBJ_BankAccountTransaction__c>{
        bat(bankBrlA.Id, 'BRL', 1000, 'CREDIT', 'brl-in'),
        bat(bankBrlA.Id, 'BRL', 300, 'DEBIT', 'brl-out'),
        bat(bankBrlB.Id, 'BRL', 200, 'CREDIT', 'brl-b'),
        bat(bankUsdA.Id, 'USD', 20, 'CREDIT', 'usd-in'),
        bat(bankUsdA.Id, 'USD', 80, 'DEBIT', 'usd-out')
      };
      Datetime buyAt = System.now().addMinutes(-30);
      Datetime sellAt = System.now().addMinutes(-10);
      quote('USD', 'BRL', 5.0033, buyAt, 'BUY', 'usd-buy');
      quote('USD', 'BRL', 5.1067, sellAt, 'SELL', 'usd-sell');
      Test.startTest();
      ALT_CLS_ConsolidationService.Result plain = new ALT_CLS_ConsolidationService()
        .consolidate(scope(new List<Id>{ holderA.Id, holderB.Id }, null));
      ALT_CLS_ConsolidationService.Result compared = new ALT_CLS_ConsolidationService()
        .consolidate(scope(new List<Id>{ holderA.Id, holderB.Id }, 'BRL'));
      Test.stopTest();

      // Without a reporting currency nothing is converted and nothing is compared.
      Assert.isNull(plain.reportingIso);
      Assert.isNull(plain.comparableTotal);
      Assert.isNull(total(plain, 'USD').conversionState);
      Assert.areEqual(
        80,
        total(plain, 'USD').outflow,
        'sem conversao nem paridade'
      );
      Assert.isNull(total(plain, 'USD').reportingOutflow);

      // The currency totals are the originals: only the comparison is added.
      ALT_CLS_ConsolidationService.Total usd = total(compared, 'USD');
      Assert.areEqual(20, usd.inflow, 'valor original imutavel');
      Assert.areEqual(80, usd.outflow, 'valor original imutavel');
      Assert.areEqual(
        ALT_CLS_IndicativeEquivalenceService.STATE_ESTIMATED,
        usd.conversionState
      );
      Assert.areEqual(5.0033, usd.rateInflow, 'lado de compra para a entrada');
      Assert.areEqual(5.1067, usd.rateOutflow, 'lado de venda para a saida');
      Assert.areEqual(PROVIDER, usd.rateProvider);
      Assert.areEqual(
        buyAt,
        usd.rateEffectiveAtInflow,
        'cada lado guarda a vigencia da propria cotacao'
      );
      Assert.areEqual(sellAt, usd.rateEffectiveAtOutflow);
      Assert.areEqual(
        100.07,
        usd.reportingInflow,
        '20 x 5,0033 arredondado HALF_UP'
      );
      Assert.areEqual(
        408.54,
        usd.reportingOutflow,
        '80 x 5,1067 arredondado HALF_UP'
      );
      Assert.areEqual(-308.47, usd.reportingNet);

      ALT_CLS_ConsolidationService.Total brl = total(compared, 'BRL');
      Assert.areEqual(900, brl.net, 'a moeda de reporte nao e convertida');
      Assert.areEqual(
        ALT_CLS_IndicativeEquivalenceService.STATE_SAME_CURRENCY,
        brl.conversionState
      );

      Assert.areEqual(
        ALT_CLS_ConsolidationService.CONFIDENCE_FULL,
        compared.confidence,
        'converter com cotacao utilizavel nao baixa a confianca'
      );
      Assert.isTrue(compared.reasons.isEmpty(), compared.reasons.toString());

      ALT_CLS_ConsolidationService.Total comparable = compared.comparableTotal;
      Assert.areEqual('BRL', comparable.currencyIso);
      Assert.areEqual(1300.07, comparable.inflow);
      Assert.areEqual(708.54, comparable.outflow);
      Assert.areEqual(591.53, comparable.net);
      Assert.areEqual(5, comparable.factCount);
      Assert.areEqual(
        2,
        comparable.holderCount,
        'o mesmo titular em duas moedas conta uma vez'
      );
      Assert.isNull(
        comparable.conversionState,
        'o indicador ja esta na moeda de reporte; o estado vive em cada total'
      );
    }
  }

  /** Only the side that contributes needs a quote: an inflow-only currency stays comparable. */
  @IsTest
  static void aCurrencyThatOnlyReceivedNeedsNoSellQuote() {
    System.runAs(byAlias('axf123g')) {
      Account holderA = holder('Titular A');
      AXF_OBJ_BankAccount__c bankBrl = bank(holderA.Id, 'BRL', 'a');
      AXF_OBJ_BankAccount__c bankUsd = bank(holderA.Id, 'USD', 'u');
      insert new List<AXF_OBJ_BankAccountTransaction__c>{
        bat(bankBrl.Id, 'BRL', 1000, 'CREDIT', 'brl-in'),
        bat(bankUsd.Id, 'USD', 20, 'CREDIT', 'usd-in')
      };
      quote('USD', 'BRL', 5.00, System.now(), 'BUY', 'usd-buy-only');
      Test.startTest();
      ALT_CLS_ConsolidationService.Result result = new ALT_CLS_ConsolidationService()
        .consolidate(scope(new List<Id>{ holderA.Id }, 'BRL'));
      Test.stopTest();
      ALT_CLS_ConsolidationService.Total usd = total(result, 'USD');
      Assert.areEqual(
        ALT_CLS_IndicativeEquivalenceService.STATE_ESTIMATED,
        usd.conversionState,
        'sem saida nao e preciso cotacao de venda'
      );
      Assert.areEqual(100, usd.reportingInflow);
      Assert.areEqual(0, usd.reportingOutflow);
      Assert.isNull(usd.rateOutflow);
      Assert.isNull(usd.rateEffectiveAtOutflow);
      ALT_CLS_ConsolidationService.Total comparable = result.comparableTotal;
      Assert.isNotNull(comparable, 'o indicador comparavel existe');
      Assert.areEqual(1100, comparable.inflow);
      Assert.areEqual(0, comparable.outflow);
      Assert.areEqual(1100, comparable.net);
      Assert.areEqual(2, comparable.factCount);
    }
  }

  /**
   * The read applies the ratified provider and its window: a newer row from another provider and a
   * row older than the searched range are both outside the evidence, so neither can be applied.
   */
  @IsTest
  static void onlyTheRatifiedProviderInsideTheWindowIsApplied() {
    System.runAs(byAlias('axf123g')) {
      Account holderA = holder('Titular A');
      AXF_OBJ_BankAccount__c bankUsd = bank(holderA.Id, 'USD', 'u');
      AXF_OBJ_BankAccount__c bankEur = bank(holderA.Id, 'EUR', 'e');
      insert new List<AXF_OBJ_BankAccountTransaction__c>{
        // The stored ISO is written as the source delivered it; the reference row is matched on its
        // normalized form, exactly as the indicative layer normalizes before comparing (AXF-92).
        bat(bankUsd.Id, 'usd', 80, 'DEBIT', 'usd-out'),
        bat(bankEur.Id, 'EUR', 10, 'DEBIT', 'eur-out')
      };
      quote('USD', 'BRL', 5.10, System.now().addDays(-2), 'SELL', 'usd-bcb');
      quote(
        'USD',
        'BRL',
        9.99,
        System.now().addMinutes(-30),
        'SELL',
        'usd-other',
        'OTHER_FEED'
      );
      quote('EUR', 'BRL', 6.20, System.now().addDays(-20), 'SELL', 'eur-old');
      Test.startTest();
      ALT_CLS_ConsolidationService.Result result = new ALT_CLS_ConsolidationService()
        .consolidate(scope(new List<Id>{ holderA.Id }, 'BRL'));
      Test.stopTest();
      ALT_CLS_ConsolidationService.Total usd = total(result, 'usd');
      Assert.areEqual(
        'usd',
        usd.currencyIso,
        'a moeda original nao e reescrita'
      );
      Assert.areEqual(PROVIDER, usd.rateProvider);
      Assert.areEqual(
        5.10,
        usd.rateOutflow,
        'cotacao mais nova de outro provedor nao entra'
      );
      Assert.areEqual(408.00, usd.reportingOutflow);
      ALT_CLS_ConsolidationService.Total eur = total(result, 'EUR');
      Assert.areEqual(
        ALT_CLS_IndicativeEquivalenceService.STATE_UNAVAILABLE,
        eur.conversionState,
        'linha fora da janela pesquisada nem e lida'
      );
      Assert.isNull(eur.reportingOutflow);
      Assert.isNull(
        result.comparableTotal,
        'uma moeda sem cotacao retem o indicador'
      );
      Assert.isTrue(
        result.reasons.contains('MISSING_MATERIAL_FX'),
        result.reasons.toString()
      );
    }
  }

  /** No usable quote for a currency: no number, no indicator — and never an assumed parity. */
  @IsTest
  static void aMissingQuoteWithholdsTheIndicatorWithoutAssumingParity() {
    System.runAs(byAlias('axf123g')) {
      Account holderA = holder('Titular A');
      AXF_OBJ_BankAccount__c bankBrl = bank(holderA.Id, 'BRL', 'a');
      AXF_OBJ_BankAccount__c bankUsd = bank(holderA.Id, 'USD', 'u');
      insert new List<AXF_OBJ_BankAccountTransaction__c>{
        bat(bankBrl.Id, 'BRL', 1000, 'CREDIT', 'brl-in'),
        bat(bankBrl.Id, 'BRL', 300, 'DEBIT', 'brl-out'),
        bat(bankUsd.Id, 'USD', 80, 'DEBIT', 'usd-out')
      };
      Test.startTest();
      ALT_CLS_ConsolidationService.Result result = new ALT_CLS_ConsolidationService()
        .consolidate(scope(new List<Id>{ holderA.Id }, 'BRL'));
      Test.stopTest();
      ALT_CLS_ConsolidationService.Total usd = total(result, 'USD');
      Assert.areEqual(
        ALT_CLS_IndicativeEquivalenceService.STATE_UNAVAILABLE,
        usd.conversionState
      );
      Assert.isNull(usd.reportingOutflow, 'sem taxa nao ha numero');
      Assert.isNull(usd.rateOutflow);
      Assert.areEqual(80, usd.outflow, 'o valor original permanece visivel');
      Assert.isNull(result.comparableTotal, 'o indicador comparavel e retido');
      Assert.isTrue(
        result.reasons.contains('MISSING_MATERIAL_FX'),
        result.reasons.toString()
      );
      Assert.areEqual(
        ALT_CLS_ConsolidationService.CONFIDENCE_DEGRADED,
        result.confidence
      );
      Assert.areEqual(
        700,
        total(result, 'BRL').net,
        'o total original continua'
      );
    }
  }

  /** A quote outside the validity window is stale: the number is omitted, never converted. */
  @IsTest
  static void aStaleQuoteIsNeverConverted() {
    System.runAs(byAlias('axf123g')) {
      Account holderA = holder('Titular A');
      AXF_OBJ_BankAccount__c bankBrl = bank(holderA.Id, 'BRL', 'a');
      AXF_OBJ_BankAccount__c bankUsd = bank(holderA.Id, 'USD', 'u');
      insert new List<AXF_OBJ_BankAccountTransaction__c>{
        bat(bankBrl.Id, 'BRL', 1000, 'CREDIT', 'brl-in'),
        bat(bankUsd.Id, 'USD', 80, 'DEBIT', 'usd-out')
      };
      quote('USD', 'BRL', 5.10, System.now().addDays(-10), 'SELL', 'usd-stale');
      Test.startTest();
      ALT_CLS_ConsolidationService.Result result = new ALT_CLS_ConsolidationService()
        .consolidate(scope(new List<Id>{ holderA.Id }, 'BRL'));
      Test.stopTest();
      ALT_CLS_ConsolidationService.Total usd = total(result, 'USD');
      Assert.areEqual(
        ALT_CLS_IndicativeEquivalenceService.STATE_STALE,
        usd.conversionState
      );
      Assert.isNull(usd.reportingOutflow);
      Assert.isNull(result.comparableTotal);
      Assert.isTrue(
        result.reasons.contains('MISSING_MATERIAL_FX'),
        result.reasons.toString()
      );
    }
  }

  /** The newest quote of the pair decides: a superseded older rate is never substituted for it. */
  @IsTest
  static void anUnusableNewestQuoteIsNeverReplacedByAnOlderOne() {
    System.runAs(byAlias('axf123g')) {
      Account holderA = holder('Titular A');
      AXF_OBJ_BankAccount__c bankUsd = bank(holderA.Id, 'USD', 'u');
      insert bat(bankUsd.Id, 'USD', 80, 'DEBIT', 'usd-out');
      quote('USD', 'BRL', 5.10, System.now().addDays(-2), 'SELL', 'usd-old');
      quote('USD', 'BRL', 0, System.now().addMinutes(-30), 'SELL', 'usd-zero');
      Test.startTest();
      ALT_CLS_ConsolidationService.Result result = new ALT_CLS_ConsolidationService()
        .consolidate(scope(new List<Id>{ holderA.Id }, 'BRL'));
      Test.stopTest();
      ALT_CLS_ConsolidationService.Total usd = total(result, 'USD');
      Assert.areEqual(
        ALT_CLS_IndicativeEquivalenceService.STATE_UNAVAILABLE,
        usd.conversionState,
        'cotacao mais nova inutilizavel nao cai para a antiga'
      );
      Assert.isNull(usd.reportingOutflow);
      Assert.isNull(usd.rateOutflow);
      Assert.isNull(result.comparableTotal);
    }
  }

  // ------------------------------------------------------------------------- fixtures by id

  private static AXF_OBJ_BankAccountTransaction__c factRow(Id factId) {
    return [
      SELECT
        Id,
        AXF_BAT_NUM_Magnitude__c,
        AXF_BAT_TXT_CurrencyIsoCode__c,
        AXF_BAT_PKL_Direction__c,
        AXF_BAT_PKL_Status__c,
        AXF_BAT_DAT_Date__c,
        AXF_BAT_NUM_Version__c,
        LastModifiedDate,
        SystemModstamp
      FROM AXF_OBJ_BankAccountTransaction__c
      WHERE Id = :factId
    ];
  }

  private static AXF_OBJ_EconomicAllocationSet__c setRow(Id setId) {
    return [
      SELECT
        Id,
        AXF_EAS_PKL_State__c,
        AXF_EAS_NUM_FactMagnitude__c,
        AXF_EAS_TXT_CurrencyIsoCode__c,
        AXF_EAS_LKP_HolderAccount__c,
        AXF_EAS_LKP_BankTransaction__c,
        AXF_EAS_NUM_Version__c,
        LastModifiedDate,
        SystemModstamp
      FROM AXF_OBJ_EconomicAllocationSet__c
      WHERE Id = :setId
    ];
  }

  private static List<AXF_OBJ_EconomicAllocation__c> parcelRows(Id setId) {
    return [
      SELECT
        Id,
        AXF_EA_LKP_Account__c,
        AXF_EA_NUM_Percent__c,
        AXF_EA_NUM_Magnitude__c,
        AXF_EA_TXT_CurrencyIsoCode__c,
        LastModifiedDate,
        SystemModstamp
      FROM AXF_OBJ_EconomicAllocation__c
      WHERE AXF_EA_MDR_AllocationSet__c = :setId
      ORDER BY Id
    ];
  }
}
