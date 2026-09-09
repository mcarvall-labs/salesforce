/**
 * @description Servico de dominio de encargos de liquidacao cambial (AXF-61).
 *
 * Registra tarifa/IOF/tributo/intermediario/outro comprovados, separados de spread e VET
 * (que sao metricas derivadas, nunca charge). Regras:
 * - Moeda restrita a source ou target do Settlement (moeda terceira recusada);
 * - Authority exclusiva: DERIVED_CONTRIBUTION exige ContributionKey (sem lancamento);
 *   SEPARATE_ENTRY exige Lancamento Separado (FinancialTransaction) preexistente;
 * - Encargos so podem ser adicionados enquanto o Settlement nao estiver CONFIRMED/CORRECTION/REVERSAL;
 * - IOF/tributo sem aliquota hardcoded: valor explicito do comprovante/policy versionada;
 * - Idempotencia por (Settlement, tipo + hash de evidencia) quando evidencia presente.
 * CRUD/FLS nativos (with sharing).
 */
public with sharing class ALT_CLS_FxChargeService {
  public static final String DERIVED_CONTRIBUTION = 'DERIVED_CONTRIBUTION';
  public static final String SEPARATE_ENTRY = 'SEPARATE_ENTRY';

  public class ChargeInputDTO {
    @AuraEnabled
    public Id settlementId;
    @AuraEnabled
    public String chargeType;
    @AuraEnabled
    public String treatment;
    @AuraEnabled
    public Decimal magnitude;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public String recognitionAuthority;
    @AuraEnabled
    public Id separateEntryId;
    @AuraEnabled
    public String contributionKey;
    @AuraEnabled
    public String jurisdiction;
    @AuraEnabled
    public String policyVersion;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String evidenceHash;
  }

  public class ResultDTO {
    @AuraEnabled
    public Id chargeId;
    @AuraEnabled
    public Boolean created;
    @AuraEnabled
    public Integer sequence;
    @AuraEnabled
    public String message;
  }

  public ResultDTO createCharge(ChargeInputDTO input) {
    validate(input);

    AXF_OBJ_FxSettlement__c settlement = fetchSettlement(input.settlementId);
    String sourceCurrency = settlement.AXF_FXT_TXT_SourceCurrency__c;
    String targetCurrency = settlement.AXF_FXT_TXT_CurrencyIsoCode__c;
    String currencyCode = input.currencyIso.trim().toUpperCase();
    if (currencyCode != sourceCurrency && currencyCode != targetCurrency) {
      throw new AXF_CLS_FxSettlementException(
        'Moeda do encargo deve ser a source ou target da liquidacao (moeda terceira recusada).'
      );
    }

    // Idempotencia por evidencia quando presente (replay nao duplica).
    if (String.isNotBlank(input.evidenceHash)) {
      List<AXF_OBJ_FxSettlementCharge__c> existing = [
        SELECT Id
        FROM AXF_OBJ_FxSettlementCharge__c
        WHERE
          AXF_FXC_MDR_Settlement__c = :input.settlementId
          AND AXF_FXC_PKL_ChargeType__c = :input.chargeType
          AND AXF_FXC_TXT_EvidenceHash__c = :input.evidenceHash
        LIMIT 1
      ];
      if (!existing.isEmpty()) {
        ResultDTO replay = new ResultDTO();
        replay.chargeId = existing[0].Id;
        replay.created = false;
        replay.sequence = null;
        replay.message = 'Encargo ja registrado com esta evidencia (idempotente).';
        return replay;
      }
    }

    Integer sequence = nextSequence(input.settlementId);

    AXF_OBJ_FxSettlementCharge__c charge = new AXF_OBJ_FxSettlementCharge__c();
    charge.AXF_FXC_MDR_Settlement__c = input.settlementId;
    charge.AXF_FXC_PKL_ChargeType__c = input.chargeType;
    charge.AXF_FXC_PKL_Treatment__c = input.treatment;
    charge.AXF_FXC_NUM_Magnitude__c = input.magnitude;
    charge.AXF_FXC_TXT_CurrencyIsoCode__c = currencyCode;
    charge.AXF_FXC_PKL_RecognitionAuthority__c = input.recognitionAuthority;
    charge.AXF_FXC_LKP_SeparateEntry__c = input.separateEntryId;
    charge.AXF_FXC_TXT_ContributionKey__c = input.contributionKey;
    charge.AXF_FXC_TXT_Jurisdiction__c = input.jurisdiction;
    charge.AXF_FXC_TXT_PolicyVersion__c = input.policyVersion;
    charge.AXF_FXC_TAL_Description__c = input.description;
    charge.AXF_FXC_TXT_EvidenceHash__c = input.evidenceHash;
    charge.AXF_FXC_NUM_Sequence__c = sequence;
    charge.AXF_FXC_EXI_ChargeKey__c = AXF_CLS_IdentityFraming.key(
      new List<Object>{ 'fxc-v1', input.settlementId, sequence }
    );
    charge.AXF_FXC_NUM_Version__c = 0;
    insert charge;

    ResultDTO result = new ResultDTO();
    result.chargeId = charge.Id;
    result.created = true;
    result.sequence = sequence;
    result.message = 'Encargo registrado.';
    return result;
  }

  private void validate(ChargeInputDTO input) {
    if (
      input == null ||
      input.settlementId == null ||
      input.chargeType == null
    ) {
      throw new AXF_CLS_FxSettlementException(
        'Settlement, ChargeType sao obrigatorios (AXF-61).'
      );
    }
    if (input.magnitude == null || input.magnitude <= 0) {
      throw new AXF_CLS_FxSettlementException(
        'Magnitude do encargo deve ser positiva.'
      );
    }
    if (String.isBlank(input.treatment) || String.isBlank(input.currencyIso)) {
      throw new AXF_CLS_FxSettlementException(
        'Treatment e Moeda sao obrigatorios.'
      );
    }
    if (
      input.recognitionAuthority == DERIVED_CONTRIBUTION &&
      String.isBlank(input.contributionKey)
    ) {
      throw new AXF_CLS_FxSettlementException(
        'DERIVED_CONTRIBUTION exige ContributionKey (sem lancamento separado).'
      );
    }
    if (
      input.recognitionAuthority == SEPARATE_ENTRY &&
      input.separateEntryId == null
    ) {
      throw new AXF_CLS_FxSettlementException(
        'SEPARATE_ENTRY exige Lancamento Separado (FinancialTransaction).'
      );
    }
    if (
      input.recognitionAuthority == DERIVED_CONTRIBUTION &&
      input.separateEntryId != null
    ) {
      throw new AXF_CLS_FxSettlementException(
        'DERIVED_CONTRIBUTION nao pode ter lancamento separado (XOR).'
      );
    }
  }

  private AXF_OBJ_FxSettlement__c fetchSettlement(Id settlementId) {
    List<AXF_OBJ_FxSettlement__c> settlements = [
      SELECT
        Id,
        AXF_FXT_PKL_State__c,
        AXF_FXT_TXT_SourceCurrency__c,
        AXF_FXT_TXT_CurrencyIsoCode__c
      FROM AXF_OBJ_FxSettlement__c
      WHERE Id = :settlementId
      LIMIT 1
    ];
    if (settlements.isEmpty()) {
      throw new AXF_CLS_FxSettlementException('Liquidacao nao encontrada.');
    }
    String state = settlements[0].AXF_FXT_PKL_State__c;
    if (state == 'CONFIRMED' || state == 'CORRECTION' || state == 'REVERSAL') {
      throw new AXF_CLS_FxSettlementException(
        'Encargos nao podem ser adicionados a liquidacoes ' + state + '.'
      );
    }
    return settlements[0];
  }

  private Integer nextSequence(Id settlementId) {
    AggregateResult agg = [
      SELECT MAX(AXF_FXC_NUM_Sequence__c) maxSeq
      FROM AXF_OBJ_FxSettlementCharge__c
      WHERE AXF_FXC_MDR_Settlement__c = :settlementId
    ];
    Integer current = agg.get('maxSeq') == null
      ? 0
      : Integer.valueOf(agg.get('maxSeq'));
    return current + 1;
  }
}
