/**
 * @description Servico de dominio da Liquidacao Cambial em rascunho (AXF-59).
 *
 * Registra os termos efetivos da operacao INBOUND|OUTBOUND separando moedas,
 * esperado/entregue/convertido, taxa efetiva (target per 1 source), referencia
 * (PTAX) e datas - sem inventar taxa, encargo ou valor:
 * - Dados ausentes no rascunho -> State PENDING_DETAILS (preserva caixa observado
 *   ja conhecido; metricas incompletas marcadas pelo proprio estado).
 * - ExchangeRate permanece referencia separada (lookup AXF_FXT_LKP_ReferenceRate__c).
 * - Idempotencia por SettlementKey = SHA256(frame(Account, Provider, OperationKey)).
 * CRUD/FLS nativos (with sharing); sem Delete; confirmacao/correcao/estorno em stories
 * posteriores (AXF-60/62/63) com novos registros - nunca edita confirmado.
 */
public with sharing class ALT_CLS_FxSettlementService {
  public static final String PROVIDER_MANUAL = 'MANUAL';
  public static final String STATE_DRAFT = 'DRAFT';
  public static final String STATE_PENDING_DETAILS = 'PENDING_DETAILS';
  public static final String KIND_PRIMARY = 'PRIMARY';
  public static final String EVIDENCE_NONE = 'NONE';

  public class DraftInputDTO {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public String sourceCurrency;
    @AuraEnabled
    public String targetCurrency;
    @AuraEnabled
    public Decimal expectedSource;
    @AuraEnabled
    public Decimal deliveredSource;
    @AuraEnabled
    public Decimal convertedSource;
    @AuraEnabled
    public Decimal effectiveRate;
    @AuraEnabled
    public Decimal referenceRate;
    @AuraEnabled
    public Id referenceRateId;
    @AuraEnabled
    public Decimal grossTargetAmount;
    @AuraEnabled
    public Decimal netBankMovement;
    @AuraEnabled
    public Date tradeDate;
    @AuraEnabled
    public Date valueDate;
    @AuraEnabled
    public Date postingDate;
    @AuraEnabled
    public String timeZone;
    @AuraEnabled
    public String operationKey;
    @AuraEnabled
    public String evidenceHash;
  }

  public class ResultDTO {
    @AuraEnabled
    public Id settlementId;
    @AuraEnabled
    public Boolean created;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public String message;
  }

  public ResultDTO createDraft(DraftInputDTO input) {
    validate(input);

    String provider = PROVIDER_MANUAL;
    String operationKey = String.isBlank(input.operationKey)
      ? 'man-' + AXF_CLS_IdentityFraming.sha256Hex(String.valueOf(Datetime.now().getTime())).substring(0, 20)
      : input.operationKey.trim();

    String settlementKey = AXF_CLS_IdentityFraming.key(
      new List<Object>{ 'fxt-v1', String.valueOf(input.accountId), provider, operationKey }
    );

    // Replay/idempotencia por chave (G6).
    List<AXF_OBJ_FxSettlement__c> existing = [
      SELECT Id, AXF_FXT_PKL_State__c
      FROM AXF_OBJ_FxSettlement__c
      WHERE AXF_FXT_EXI_SettlementKey__c = :settlementKey
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      ResultDTO replay = new ResultDTO();
      replay.settlementId = existing[0].Id;
      replay.created = false;
      replay.state = existing[0].AXF_FXT_PKL_State__c;
      replay.message = 'Liquidacao ja registrada (idempotente).';
      return replay;
    }

    AXF_OBJ_FxSettlement__c settlement = new AXF_OBJ_FxSettlement__c();
    settlement.AXF_FXT_LKP_Account__c = input.accountId;
    settlement.AXF_FXT_PKL_Direction__c = input.direction;
    settlement.AXF_FXT_TXT_SourceCurrency__c = input.sourceCurrency;
    settlement.AXF_FXT_TXT_CurrencyIsoCode__c = input.targetCurrency;
    settlement.AXF_FXT_NUM_ExpectedSource__c = input.expectedSource;
    settlement.AXF_FXT_NUM_DeliveredSource__c = input.deliveredSource;
    settlement.AXF_FXT_NUM_ConvertedSource__c = input.convertedSource;
    settlement.AXF_FXT_NUM_EffectiveRate__c = input.effectiveRate;
    settlement.AXF_FXT_NUM_ReferenceRate__c = input.referenceRate;
    settlement.AXF_FXT_LKP_ReferenceRate__c = input.referenceRateId;
    settlement.AXF_FXT_CUR_GrossTargetAmount__c = input.grossTargetAmount;
    settlement.AXF_FXT_CUR_NetBankMovement__c = input.netBankMovement;
    settlement.AXF_FXT_DAT_TradeDate__c = input.tradeDate;
    settlement.AXF_FXT_DAT_ValueDate__c = input.valueDate;
    settlement.AXF_FXT_DAT_PostingDate__c = input.postingDate;
    settlement.AXF_FXT_TXT_TimeZone__c = input.timeZone;
    settlement.AXF_FXT_TXT_OperationKey__c = operationKey;
    settlement.AXF_FXT_EXI_SettlementKey__c = settlementKey;
    settlement.AXF_FXT_TXT_Provider__c = provider;
    settlement.AXF_FXT_PKL_Kind__c = KIND_PRIMARY;
    settlement.AXF_FXT_PKL_State__c = hasCompleteDetails(input)
      ? STATE_DRAFT
      : STATE_PENDING_DETAILS;
    settlement.AXF_FXT_TXT_EvidenceHash__c = input.evidenceHash;
    settlement.AXF_FXT_PKL_EvidenceStatus__c = String.isBlank(input.evidenceHash)
      ? EVIDENCE_NONE
      : 'ATTACHED';
    settlement.AXF_FXT_NUM_Version__c = 0;
    insert settlement;

    ResultDTO result = new ResultDTO();
    result.settlementId = settlement.Id;
    result.created = true;
    result.state = settlement.AXF_FXT_PKL_State__c;
    result.message = settlement.AXF_FXT_PKL_State__c == STATE_PENDING_DETAILS
      ? 'Rascunho salvo com dados pendentes (sem presumir taxa/encargo).'
      : 'Rascunho salvo.';
    return result;
  }

  /** Rascunho completo exige os termos efetivos principais; ausencia vira PENDING_DETAILS (AC 2). */
  private Boolean hasCompleteDetails(DraftInputDTO input) {
    return input.deliveredSource != null &&
      input.effectiveRate != null &&
      input.grossTargetAmount != null &&
      input.valueDate != null;
  }

  private void validate(DraftInputDTO input) {
    if (input == null || input.accountId == null || input.direction == null) {
      throw new AXF_CLS_FxSettlementException(
        'Titular (Account) e Direcao sao obrigatorios (AXF-59).'
      );
    }
    if (input.direction != 'INBOUND' && input.direction != 'OUTBOUND') {
      throw new AXF_CLS_FxSettlementException('Direcao invalida (INBOUND|OUTBOUND).');
    }
    if (
      String.isBlank(input.sourceCurrency) ||
      String.isBlank(input.targetCurrency)
    ) {
      throw new AXF_CLS_FxSettlementException(
        'Moedas source e target sao obrigatorias.'
      );
    }
    if (input.expectedSource != null && input.expectedSource < 0) {
      throw new AXF_CLS_FxSettlementException(
        'Magnitudes devem ser nao negativas (Money contract).'
      );
    }
    if (input.deliveredSource != null && input.deliveredSource < 0) {
      throw new AXF_CLS_FxSettlementException(
        'Magnitudes devem ser nao negativas (Money contract).'
      );
    }
    if (input.effectiveRate != null && input.effectiveRate < 0) {
      throw new AXF_CLS_FxSettlementException('Taxa efetiva deve ser nao negativa.');
    }
  }
}
