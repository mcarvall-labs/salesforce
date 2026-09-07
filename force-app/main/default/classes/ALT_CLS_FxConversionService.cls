/**
 * @description Servico de conversao com snapshot cambial rastreavel (AXF-24).
 *
 * Preserva magnitude/moeda originais e congela em FxApplicationSnapshot (FXS) a taxa,
 * fonte (ExchangeRate), data, lado, policy e arredondamento aplicados. Historico usa o
 * snapshot, nunca a taxa corrente. PTAX BCB com busca retroativa maxima de 5 dias;
 * taxa ausente -> MISSING_RATE (o chamador pode excluir explicitamente o ativo e baixar
 * confianca). Imutavel: correcao = sucessor + SUPERSEDED.
 */
public with sharing class ALT_CLS_FxConversionService {
  public static final String PROVIDER_BCB_PTAX = 'BCB_PTAX';
  public static final Integer MAX_LOOKBACK_DAYS = 5;

  public class ConversionInputDTO {
    @AuraEnabled
    public String targetType; // FINANCIAL_TRANSACTION | FX_SETTLEMENT_CHARGE
    @AuraEnabled
    public Id targetId;
    @AuraEnabled
    public String purpose; // RECOGNITION | SETTLEMENT | ISSUANCE | CHARGE | CURRENT_REVALUATION
    @AuraEnabled
    public String reportingIso;
    @AuraEnabled
    public String side; // BUY | SELL (opcional)
    @AuraEnabled
    public String policyVersion;
    @AuraEnabled
    public String roundingPolicy;
  }

  public class ConversionResultDTO {
    @AuraEnabled
    public Id snapshotId;
    @AuraEnabled
    public Boolean converted;
    @AuraEnabled
    public String outcome; // CONVERTED | SAME_CURRENCY | MISSING_RATE
    @AuraEnabled
    public Decimal originalAmount;
    @AuraEnabled
    public String originalIso;
    @AuraEnabled
    public Decimal reportingAmount;
    @AuraEnabled
    public String reportingIso;
    @AuraEnabled
    public Decimal rateUsed;
    @AuraEnabled
    public String message;
  }

  public ConversionResultDTO applyConversion(ConversionInputDTO input) {
    validate(input);

    FxTarget target = loadTarget(input);
    if (target.originalIso == input.reportingIso) {
      ConversionResultDTO same = baseResult(input, target);
      same.converted = false;
      same.outcome = 'SAME_CURRENCY';
      same.message = 'Moeda original ja e a de reporte; nenhum snapshot necessario.';
      return same;
    }

    AXF_OBJ_ExchangeRate__c rate = findRate(
      target.originalIso,
      input.reportingIso,
      target.valueDate,
      input.side
    );
    if (rate == null) {
      ConversionResultDTO missing = baseResult(input, target);
      missing.converted = false;
      missing.outcome = 'MISSING_RATE';
      missing.message =
        'Sem taxa ' +
        PROVIDER_BCB_PTAX +
        ' em ate ' +
        MAX_LOOKBACK_DAYS +
        ' dias; valor original permanece visivel (exclusao explicita a cargo do chamador).';
      return missing;
    }

    Decimal reportingAmount = (target.originalAmount * rate.AXF_EXR_NUM_Rate__c)
      .setScale(2, System.RoundingMode.HALF_UP);

    // Idempotencia: mesma aplicacao (alvo/finalidade/taxa/origem/convertido) reutiliza o snapshot.
    String revisionKey = applicationKey(
      input.targetType,
      input.targetId,
      input.purpose,
      1
    );
    List<AXF_OBJ_FxApplicationSnapshot__c> existing = [
      SELECT Id
      FROM AXF_OBJ_FxApplicationSnapshot__c
      WHERE AXF_FXS_EXI_ApplicationKey__c = :revisionKey
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      ConversionResultDTO replay = baseResult(input, target);
      replay.snapshotId = existing[0].Id;
      replay.converted = true;
      replay.outcome = 'CONVERTED';
      replay.reportingAmount = reportingAmount;
      replay.reportingIso = input.reportingIso;
      replay.rateUsed = rate.AXF_EXR_NUM_Rate__c;
      replay.message = 'Snapshot ja existente (idempotente).';
      return replay;
    }

    AXF_OBJ_FxApplicationSnapshot__c snapshot = buildSnapshot(
      input,
      target,
      rate,
      reportingAmount
    );
    insert snapshot;

    ConversionResultDTO result = baseResult(input, target);
    result.snapshotId = snapshot.Id;
    result.converted = true;
    result.outcome = 'CONVERTED';
    result.reportingAmount = reportingAmount;
    result.reportingIso = input.reportingIso;
    result.rateUsed = rate.AXF_EXR_NUM_Rate__c;
    result.message = 'Snapshot de conversao criado.';
    return result;
  }

  private AXF_OBJ_FxApplicationSnapshot__c buildSnapshot(
    ConversionInputDTO input,
    FxTarget target,
    AXF_OBJ_ExchangeRate__c rate,
    Decimal reportingAmount
  ) {
    AXF_OBJ_FxApplicationSnapshot__c snapshot = new AXF_OBJ_FxApplicationSnapshot__c();
    snapshot.AXF_FXS_PKL_TargetType__c = input.targetType;
    if (input.targetType == 'FINANCIAL_TRANSACTION') {
      snapshot.AXF_FXS_LKP_FinancialTransaction__c = input.targetId;
    } else {
      snapshot.AXF_FXS_LKP_FxSettlementCharge__c = input.targetId;
    }
    snapshot.AXF_FXS_PKL_Purpose__c = input.purpose;
    snapshot.AXF_FXS_NUM_OriginalAmount__c = target.originalAmount;
    snapshot.AXF_FXS_TXT_OriginalIso__c = target.originalIso;
    snapshot.AXF_FXS_NUM_ReportingAmount__c = reportingAmount;
    snapshot.AXF_FXS_TXT_CurrencyIsoCode__c = input.reportingIso;
    snapshot.AXF_FXS_NUM_ActualRate__c = rate.AXF_EXR_NUM_Rate__c;
    snapshot.AXF_FXS_NUM_ReferenceRate__c = rate.AXF_EXR_NUM_Rate__c;
    snapshot.AXF_FXS_LKP_RateSource__c = rate.Id;
    snapshot.AXF_FXS_PKL_Side__c = input.side;
    snapshot.AXF_FXS_DAT_TradeDate__c = target.tradeDate;
    snapshot.AXF_FXS_DAT_ValueDate__c = target.valueDate;
    snapshot.AXF_FXS_TXT_PolicyVersion__c = input.policyVersion;
    snapshot.AXF_FXS_TXT_RoundingPolicy__c = input.roundingPolicy;
    snapshot.AXF_FXS_PKL_State__c = 'ACTIVE';
    snapshot.AXF_FXS_LKP_ActorUser__c = UserInfo.getUserId();
    snapshot.AXF_FXS_DT_AppliedAt__c = System.now();
    snapshot.AXF_FXS_NUM_Revision__c = 1;
    snapshot.AXF_FXS_EXI_ApplicationKey__c = applicationKey(
      input.targetType,
      input.targetId,
      input.purpose,
      1
    );
    snapshot.AXF_FXS_NUM_Version__c = 0;
    snapshot.OwnerId = target.accountOwnerId;
    return snapshot;
  }

  private ConversionResultDTO baseResult(
    ConversionInputDTO input,
    FxTarget target
  ) {
    ConversionResultDTO result = new ConversionResultDTO();
    result.originalAmount = target.originalAmount;
    result.originalIso = target.originalIso;
    result.converted = false;
    return result;
  }

  private FxTarget loadTarget(ConversionInputDTO input) {
    FxTarget target = new FxTarget();
    if (input.targetType == 'FINANCIAL_TRANSACTION') {
      List<AXF_OBJ_FinancialTransaction__c> rows = [
        SELECT
          Id,
          AXF_FTX_NUM_Magnitude__c,
          AXF_FTX_TXT_CurrencyIsoCode__c,
          AXF_FTX_DAT_PurchaseDate__c,
          AXF_FTX_DAT_DueDate__c,
          AXF_FTX_LKP_Account__r.OwnerId
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id = :input.targetId
        LIMIT 1
      ];
      if (rows.isEmpty()) {
        throw new AXF_CLS_FxSettlementException(
          'FinancialTransaction nao encontrada.'
        );
      }
      target.originalAmount = rows[0].AXF_FTX_NUM_Magnitude__c;
      target.originalIso = rows[0].AXF_FTX_TXT_CurrencyIsoCode__c;
      target.tradeDate = rows[0].AXF_FTX_DAT_PurchaseDate__c;
      target.valueDate = rows[0].AXF_FTX_DAT_DueDate__c == null
        ? rows[0].AXF_FTX_DAT_PurchaseDate__c
        : rows[0].AXF_FTX_DAT_DueDate__c;
      target.accountOwnerId = rows[0].AXF_FTX_LKP_Account__r.OwnerId;
      if (target.valueDate == null) {
        target.valueDate = Date.today();
      }
    } else {
      List<AXF_OBJ_FxSettlementCharge__c> rows = [
        SELECT
          Id,
          AXF_FXC_NUM_Magnitude__c,
          AXF_FXC_TXT_CurrencyIsoCode__c,
          AXF_FXC_MDR_Settlement__r.AXF_FXT_LKP_Account__r.OwnerId,
          AXF_FXC_MDR_Settlement__r.AXF_FXT_DAT_ValueDate__c
        FROM AXF_OBJ_FxSettlementCharge__c
        WHERE Id = :input.targetId
        LIMIT 1
      ];
      if (rows.isEmpty()) {
        throw new AXF_CLS_FxSettlementException(
          'Encargo de liquidacao nao encontrado.'
        );
      }
      target.originalAmount = rows[0].AXF_FXC_NUM_Magnitude__c;
      target.originalIso = rows[0].AXF_FXC_TXT_CurrencyIsoCode__c;
      target.tradeDate = rows[0]
        .AXF_FXC_MDR_Settlement__r.AXF_FXT_DAT_ValueDate__c;
      target.valueDate = rows[0]
        .AXF_FXC_MDR_Settlement__r.AXF_FXT_DAT_ValueDate__c;
      target.accountOwnerId = rows[0]
        .AXF_FXC_MDR_Settlement__r.AXF_FXT_LKP_Account__r.OwnerId;
      if (target.valueDate == null) {
        target.valueDate = Date.today();
      }
    }
    return target;
  }

  /** Busca cotacao BCB_PTAX do par com lookback retroativo maximo de 5 dias (lado gravado no snapshot). */
  private AXF_OBJ_ExchangeRate__c findRate(
    String baseIso,
    String quoteIso,
    Date effectiveDate,
    String side
  ) {
    Date earliest = effectiveDate.addDays(-MAX_LOOKBACK_DAYS);
    List<AXF_OBJ_ExchangeRate__c> rates = [
      SELECT Id, AXF_EXR_NUM_Rate__c, AXF_EXR_DT_EffectiveDateTime__c
      FROM AXF_OBJ_ExchangeRate__c
      WHERE
        AXF_EXR_TXT_BaseCurrency__c = :baseIso
        AND AXF_EXR_TXT_QuoteCurrency__c = :quoteIso
        AND AXF_EXR_TXT_Provider__c = :PROVIDER_BCB_PTAX
        AND AXF_EXR_DT_EffectiveDateTime__c >= :earliest
      ORDER BY AXF_EXR_DT_EffectiveDateTime__c DESC
      LIMIT 1
    ];
    return rates.isEmpty() ? null : rates[0];
  }

  private String applicationKey(
    String targetType,
    Id targetId,
    String purpose,
    Integer revision
  ) {
    return AXF_CLS_IdentityFraming.key(
      new List<Object>{ 'fxs-v1', targetType, targetId, purpose, revision }
    );
  }

  private void validate(ConversionInputDTO input) {
    if (
      input == null ||
      input.targetId == null ||
      input.purpose == null ||
      String.isBlank(input.reportingIso)
    ) {
      throw new AXF_CLS_FxSettlementException(
        'Target, Finalidade e Moeda de Reporte sao obrigatorios (AXF-24).'
      );
    }
    if (
      input.targetType != 'FINANCIAL_TRANSACTION' &&
      input.targetType != 'FX_SETTLEMENT_CHARGE'
    ) {
      throw new AXF_CLS_FxSettlementException(
        'TargetType invalido para conversao.'
      );
    }
  }

  private class FxTarget {
    public Decimal originalAmount;
    public String originalIso;
    public Date tradeDate;
    public Date valueDate;
    public Id accountOwnerId;
  }
}
