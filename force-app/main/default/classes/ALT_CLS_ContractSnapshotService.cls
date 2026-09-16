/**
 * @description Servico de dominio da preservacao contratual (AXF-57): cria o
 * ContractApplicationSnapshot (CAS) imutavel 1:1 do termo aplicado a uma ocorrencia
 * (FinancialTransaction gerada ou ACTUAL_ONLY), registra overrides manuais com
 * proveniencia por campo (DEFAULTED|OVERRIDDEN) e governa a supersessao (sucessor +
 * SUPERSEDED). Evidencia = proprio CAS imutavel + Field History (AuditEvent retirado).
 *
 * Principios (fechamento G1/G2 - dominio de contratos, 06/09/2026):
 * - CAS root privado; Lookups required FinancialTransaction/Contract/TermVersion;
 *   sem FinancialEntity (titular deriva do FTX). Identidade =
 *   SHA256(frame(FTX.PlanIdentityHash, TermVersion.Revision)); max. 1 ACTIVE por (alvo, revisao).
 * - Conteudo congelado na criacao; correcao nunca edita: cria sucessor e marca o anterior SUPERSEDED.
 * - Regeneracao futura (AXF-55) preserva overrides: campos OVERRIDDEN mantem o valor efetivo
 *   do FinancialTransaction e nao sao sobrescritos por novos defaults.
 * - CRUD/FLS nativos: toda consulta/mutacao roda em modo with sharing.
 */
public with sharing class ALT_CLS_ContractSnapshotService {
  public static final String STATE_ACTIVE = 'ACTIVE';
  public static final String STATE_SUPERSEDED = 'SUPERSEDED';
  public static final String PROV_DEFAULTED = 'DEFAULTED';
  public static final String PROV_OVERRIDDEN = 'OVERRIDDEN';
  public static final Integer PROVENANCE_SCHEMA_VERSION = 1;
  public static final String TERM_STATUS_ACTIVE = 'ACTIVE';

  /** Campos de saida da ocorrencia passiveis de override (whitelist estrita). */
  private static final Map<String, String> OVERRIDEABLE_FIELDS = new Map<String, String>{
    'AXF_FTX_NUM_Magnitude__c' => 'Decimal',
    'AXF_FTX_DAT_DueDate__c' => 'Date'
  };

  /** Campos congelados do CAS (nunca editados apos criacao). */
  public static final Set<String> FROZEN_CONTENT_FIELDS = new Set<String>{
    'AXF_CAS_LKP_FinancialTransaction__c',
    'AXF_CAS_LKP_Contract__c',
    'AXF_CAS_LKP_TermVersion__c',
    'AXF_CAS_EXI_ApplicationIdentityHash__c',
    'AXF_CAS_CUR_AppliedAmount__c',
    'AXF_CAS_TXT_CurrencyIsoCode__c',
    'AXF_CAS_PKL_RemunerationModel__c',
    'AXF_CAS_NUM_HoursQuantity__c',
    'AXF_CAS_NUM_Installments__c',
    'AXF_CAS_TXT_CalendarPolicyVersion__c',
    'AXF_CAS_TXT_TimeZone__c',
    'AXF_CAS_TXT_SourceTermRevision__c',
    'AXF_CAS_EXI_SourceTermHash__c'
  };

  public class SnapshotResultDTO {
    @AuraEnabled
    public Id snapshotId;
    @AuraEnabled
    public Id financialTransactionId;
    @AuraEnabled
    public Boolean created;
    @AuraEnabled
    public String identityHash;
  }

  public class SnapshotInputDTO {
    @AuraEnabled
    public Id financialTransactionId;
    @AuraEnabled
    public Id termVersionId;
  }

  public class OverrideInputDTO {
    @AuraEnabled
    public Id financialTransactionId;
    @AuraEnabled
    public String fieldApiName;
    @AuraEnabled
    public Object newValue;
    @AuraEnabled
    public String reason;
  }

  /**
   * @description Aplica um TermVersion a uma ocorrencia criando/atualizando o CAS vigente.
   * Idempotente por identidade (mesmo plano+revisao reutiliza o CAS ACTIVE).
   */
  public SnapshotResultDTO applyToOccurrence(SnapshotInputDTO input) {
    if (
      input == null ||
      input.financialTransactionId == null ||
      input.termVersionId == null
    ) {
      throw new AXF_CLS_ContractException(
        'FinancialTransaction e TermVersion sao obrigatorios.'
      );
    }

    AXF_OBJ_FinancialTransaction__c ftx = fetchFinancialTransaction(
      input.financialTransactionId
    );
    if (ftx == null) {
      throw new AXF_CLS_ContractException(
        'FinancialTransaction nao encontrado.'
      );
    }
    if (String.isBlank(ftx.AXF_FTX_EXI_PlanIdentityHash__c)) {
      throw new AXF_CLS_ContractException(
        'Ocorrencia contratual exige PlanIdentityHash antes do snapshot (G6).'
      );
    }

    AXF_OBJ_ContractTermVersion__c term = fetchTermVersion(input.termVersionId);
    if (term == null) {
      throw new AXF_CLS_ContractException(
        'ContractTermVersion nao encontrada.'
      );
    }
    if (term.AXF_CTV_PKL_Status__c != TERM_STATUS_ACTIVE) {
      throw new AXF_CLS_ContractException(
        'Somente TermVersion ACTIVE pode ser aplicada.'
      );
    }

    AXF_OBJ_Contract__c contract = fetchContract(term.AXF_CTV_LKP_Contract__c);
    if (contract == null) {
      throw new AXF_CLS_ContractException('Contrato do termo nao encontrado.');
    }
    if (ftx.AXF_FTX_LKP_Account__c != contract.AXF_CTR_LKP_Account__c) {
      throw new AXF_CLS_ContractException(
        'Cross-account proibido: FinancialTransaction e Contrato pertencem a titulares distintos.'
      );
    }

    String identityHash = buildIdentityHash(
      ftx.AXF_FTX_EXI_PlanIdentityHash__c,
      term.AXF_CTV_NUM_Revision__c
    );

    AXF_OBJ_ContractApplicationSnapshot__c active = findActiveSnapshot(
      input.financialTransactionId
    );
    if (
      active != null &&
      active.AXF_CAS_EXI_ApplicationIdentityHash__c == identityHash
    ) {
      SnapshotResultDTO existing = new SnapshotResultDTO();
      existing.snapshotId = active.Id;
      existing.financialTransactionId = ftx.Id;
      existing.created = false;
      existing.identityHash = identityHash;
      return existing;
    }

    // Novo snapshot ACTIVE; o anterior (se houver) vira SUPERSEDED com vinculo de predecessor.
    AXF_OBJ_ContractApplicationSnapshot__c cas = buildSnapshot(
      ftx,
      contract,
      term,
      identityHash,
      active == null ? null : active.Id
    );
    insert cas;

    if (active != null && active.AXF_CAS_PKL_State__c == STATE_ACTIVE) {
      active.AXF_CAS_PKL_State__c = STATE_SUPERSEDED;
      update active;
    }

    linkFinancialTransaction(ftx.Id, contract.Id, term.Id, cas.Id);

    SnapshotResultDTO result = new SnapshotResultDTO();
    result.snapshotId = cas.Id;
    result.financialTransactionId = ftx.Id;
    result.created = true;
    result.identityHash = identityHash;
    return result;
  }

  /**
   * @description Registra override manual de um campo de saida da ocorrencia contratual.
   * Preserva o default congelado no CAS, marca o campo como OVERRIDDEN na proveniencia,
   * grava motivo/ator/instante e atualiza o valor efetivo no FinancialTransaction.
   */
  public SnapshotResultDTO recordOverride(OverrideInputDTO input) {
    if (input == null || input.financialTransactionId == null) {
      throw new AXF_CLS_ContractException(
        'FinancialTransaction e obrigatorio.'
      );
    }
    if (
      String.isBlank(input.fieldApiName) ||
      !OVERRIDEABLE_FIELDS.containsKey(input.fieldApiName)
    ) {
      throw new AXF_CLS_ContractException(
        'Campo nao passivel de override nesta historia.'
      );
    }
    if (String.isBlank(input.reason)) {
      throw new AXF_CLS_ContractException(
        'Motivo do override e obrigatorio (AC 2).'
      );
    }

    AXF_OBJ_FinancialTransaction__c ftx = fetchFinancialTransaction(
      input.financialTransactionId
    );
    if (ftx == null || ftx.AXF_FTX_LKP_ContractTermVersion__c == null) {
      throw new AXF_CLS_ContractException(
        'Override so se aplica a ocorrencias contratuais (FinancialTransaction com TermVersion).'
      );
    }

    AXF_OBJ_ContractApplicationSnapshot__c cas = findActiveSnapshot(
      input.financialTransactionId
    );
    if (cas == null) {
      throw new AXF_CLS_ContractException(
        'Override requer um ContractApplicationSnapshot ACTIVE para a ocorrencia.'
      );
    }

    applyOverrideToTransaction(ftx, input.fieldApiName, input.newValue);

    // Proveniencia canonal por campo: default preservado + flag OVERRIDDEN no campo afetado.
    Map<String, String> provenance = parseProvenance(
      cas.AXF_CAS_TAL_FieldProvenance__c
    );
    provenance.put(input.fieldApiName, PROV_OVERRIDDEN);

    cas.AXF_CAS_TAL_FieldProvenance__c = serializeProvenance(provenance);
    cas.AXF_CAS_TAL_OverrideReason__c = input.reason;
    cas.AXF_CAS_LKP_OverriddenByUser__c = UserInfo.getUserId();
    cas.AXF_CAS_DT_OverriddenAt__c = System.now();
    cas.AXF_CAS_NUM_Version__c =
      (cas.AXF_CAS_NUM_Version__c == null ? 0 : cas.AXF_CAS_NUM_Version__c) + 1;
    update cas;

    SnapshotResultDTO result = new SnapshotResultDTO();
    result.snapshotId = cas.Id;
    result.financialTransactionId = ftx.Id;
    result.created = false;
    result.identityHash = cas.AXF_CAS_EXI_ApplicationIdentityHash__c;
    return result;
  }

  /**
   * @description Identidade canonica do CAS: SHA256(frame(PlanIdentityHash, Revision)) (fechamento G1/G2 06/09).
   */
  public static String buildIdentityHash(
    String planIdentityHash,
    Decimal revision
  ) {
    if (String.isBlank(planIdentityHash) || revision == null) {
      throw new AXF_CLS_ContractException(
        'Identidade do CAS exige PlanIdentityHash e Revision do termo (G6).'
      );
    }
    return AXF_CLS_IdentityFraming.key(
      new List<Object>{ planIdentityHash, String.valueOf(revision.longValue()) }
    );
  }

  // ---------- helpers internos ----------

  private AXF_OBJ_ContractApplicationSnapshot__c buildSnapshot(
    AXF_OBJ_FinancialTransaction__c ftx,
    AXF_OBJ_Contract__c contract,
    AXF_OBJ_ContractTermVersion__c term,
    String identityHash,
    Id predecessorId
  ) {
    AXF_OBJ_ContractApplicationSnapshot__c cas = new AXF_OBJ_ContractApplicationSnapshot__c();
    cas.AXF_CAS_LKP_FinancialTransaction__c = ftx.Id;
    cas.AXF_CAS_LKP_Contract__c = contract.Id;
    cas.AXF_CAS_LKP_TermVersion__c = term.Id;
    cas.AXF_CAS_LKP_PredecessorSnapshot__c = predecessorId;
    cas.AXF_CAS_EXI_ApplicationIdentityHash__c = identityHash;
    cas.AXF_CAS_PKL_State__c = STATE_ACTIVE;
    cas.AXF_CAS_CUR_AppliedAmount__c = term.AXF_CTV_CUR_ContractedAmount__c;
    cas.AXF_CAS_TXT_CurrencyIsoCode__c = term.AXF_CTV_TXT_CurrencyIsoCode__c;
    cas.AXF_CAS_PKL_RemunerationModel__c = term.AXF_CTV_PKL_RemunerationModel__c;
    cas.AXF_CAS_NUM_HoursQuantity__c = term.AXF_CTV_NUM_HoursQuantity__c;
    cas.AXF_CAS_NUM_Installments__c = term.AXF_CTV_NUM_Installments__c;
    cas.AXF_CAS_TXT_CalendarPolicyVersion__c = term.AXF_CTV_TXT_CalendarPolicy__c;
    cas.AXF_CAS_TXT_TimeZone__c = term.AXF_CTV_TXT_TimeZone__c;
    cas.AXF_CAS_TXT_SourceTermRevision__c = String.valueOf(
      term.AXF_CTV_NUM_Revision__c
    );
    cas.AXF_CAS_EXI_SourceTermHash__c = sourceTermHash(contract, term);

    Map<String, String> provenance = new Map<String, String>();
    provenance.put('AXF_FTX_NUM_Magnitude__c', PROV_DEFAULTED);
    provenance.put('AXF_FTX_DAT_DueDate__c', PROV_DEFAULTED);
    cas.AXF_CAS_TAL_FieldProvenance__c = serializeProvenance(provenance);
    cas.AXF_CAS_NUM_Version__c = 0;
    return cas;
  }

  /** Hash deterministico do conteudo material do termo (sem IDs de org). */
  private String sourceTermHash(
    AXF_OBJ_Contract__c contract,
    AXF_OBJ_ContractTermVersion__c term
  ) {
    return AXF_CLS_IdentityFraming.key(
      new List<Object>{
        'ctv-applied-v1',
        contract.AXF_CTR_EXI_ContractKey__c,
        String.valueOf(term.AXF_CTV_NUM_Revision__c),
        term.AXF_CTV_PKL_RemunerationModel__c,
        term.AXF_CTV_CUR_ContractedAmount__c,
        term.AXF_CTV_TXT_CurrencyIsoCode__c,
        term.AXF_CTV_NUM_Installments__c,
        term.AXF_CTV_NUM_HoursQuantity__c,
        term.AXF_CTV_TXT_CalendarPolicy__c,
        term.AXF_CTV_TXT_TimeZone__c
      }
    );
  }

  private void applyOverrideToTransaction(
    AXF_OBJ_FinancialTransaction__c ftx,
    String fieldApiName,
    Object newValue
  ) {
    if (newValue == null) {
      throw new AXF_CLS_ContractException('Valor do override e obrigatorio.');
    }
    String type = OVERRIDEABLE_FIELDS.get(fieldApiName);
    if (type == 'Decimal') {
      Decimal parsed = Decimal.valueOf(String.valueOf(newValue));
      if (parsed < 0) {
        throw new AXF_CLS_ContractException(
          'Magnitude deve ser nao negativa (Money contract).'
        );
      }
      ftx.put(fieldApiName, parsed);
    } else if (type == 'Date') {
      ftx.put(fieldApiName, Date.valueOf(String.valueOf(newValue)));
    } else {
      throw new AXF_CLS_ContractException(
        'Tipo de campo nao suportado para override.'
      );
    }
    update ftx;
  }

  private void linkFinancialTransaction(
    Id ftxId,
    Id contractId,
    Id termId,
    Id snapshotId
  ) {
    AXF_OBJ_FinancialTransaction__c ftx = new AXF_OBJ_FinancialTransaction__c(
      Id = ftxId,
      AXF_FTX_LKP_Contract__c = contractId,
      AXF_FTX_LKP_ContractTermVersion__c = termId,
      AXF_FTX_LKP_ContractApplicationSnapshot__c = snapshotId
    );
    update ftx;
  }

  private AXF_OBJ_FinancialTransaction__c fetchFinancialTransaction(Id ftxId) {
    return [
      SELECT
        Id,
        AXF_FTX_LKP_Account__c,
        AXF_FTX_EXI_PlanIdentityHash__c,
        AXF_FTX_LKP_Contract__c,
        AXF_FTX_LKP_ContractTermVersion__c,
        AXF_FTX_LKP_ContractApplicationSnapshot__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_DAT_DueDate__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id = :ftxId
      LIMIT 1
    ];
  }

  private AXF_OBJ_ContractTermVersion__c fetchTermVersion(Id termId) {
    return [
      SELECT
        Id,
        AXF_CTV_LKP_Contract__c,
        AXF_CTV_NUM_Revision__c,
        AXF_CTV_PKL_Status__c,
        AXF_CTV_PKL_RemunerationModel__c,
        AXF_CTV_CUR_ContractedAmount__c,
        AXF_CTV_TXT_CurrencyIsoCode__c,
        AXF_CTV_NUM_Installments__c,
        AXF_CTV_NUM_HoursQuantity__c,
        AXF_CTV_TXT_CalendarPolicy__c,
        AXF_CTV_TXT_TimeZone__c
      FROM AXF_OBJ_ContractTermVersion__c
      WHERE Id = :termId
      LIMIT 1
    ];
  }

  private AXF_OBJ_Contract__c fetchContract(Id contractId) {
    return [
      SELECT Id, AXF_CTR_LKP_Account__c, AXF_CTR_EXI_ContractKey__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :contractId
      LIMIT 1
    ];
  }

  private AXF_OBJ_ContractApplicationSnapshot__c findActiveSnapshot(Id ftxId) {
    List<AXF_OBJ_ContractApplicationSnapshot__c> snaps = [
      SELECT
        Id,
        AXF_CAS_EXI_ApplicationIdentityHash__c,
        AXF_CAS_PKL_State__c,
        AXF_CAS_TAL_FieldProvenance__c,
        AXF_CAS_TAL_OverrideReason__c,
        AXF_CAS_NUM_Version__c
      FROM AXF_OBJ_ContractApplicationSnapshot__c
      WHERE
        AXF_CAS_LKP_FinancialTransaction__c = :ftxId
        AND AXF_CAS_PKL_State__c = :STATE_ACTIVE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    return snaps.isEmpty() ? null : snaps[0];
  }

  /** JSON canonico: {"schemaVersion":1,"fields":{campo:DEFAULTED|OVERRIDDEN}}. */
  public static String serializeProvenance(Map<String, String> fields) {
    if (fields == null || fields.isEmpty()) {
      throw new AXF_CLS_ContractException('Proveniencia nao pode ser vazia.');
    }
    for (String field : fields.keySet()) {
      String value = fields.get(field);
      if (value != PROV_DEFAULTED && value != PROV_OVERRIDDEN) {
        throw new AXF_CLS_ContractException(
          'Proveniencia invalida para ' + field + ': ' + value
        );
      }
    }
    Map<String, Object> root = new Map<String, Object>();
    root.put('schemaVersion', PROVENANCE_SCHEMA_VERSION);
    root.put('fields', fields);
    return JSON.serialize(root);
  }

  /** Le a proveniencia canonal; retorna mapa campo -> DEFAULTED|OVERRIDDEN. */
  public static Map<String, String> parseProvenance(String serialized) {
    Map<String, String> result = new Map<String, String>();
    if (String.isBlank(serialized)) {
      return result;
    }
    try {
      Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(
        serialized
      );
      if (root == null || root.get('schemaVersion') == null) {
        throw new AXF_CLS_ContractException('Proveniencia sem schemaVersion.');
      }
      Object fieldsObj = root.get('fields');
      if (fieldsObj instanceof Map<String, Object>) {
        Map<String, Object> fields = (Map<String, Object>) fieldsObj;
        for (String field : fields.keySet()) {
          String value = String.valueOf(fields.get(field));
          if (value != PROV_DEFAULTED && value != PROV_OVERRIDDEN) {
            throw new AXF_CLS_ContractException(
              'Proveniencia invalida para ' + field + ': ' + value
            );
          }
          result.put(field, value);
        }
      }
      return result;
    } catch (AXF_CLS_ContractException ce) {
      throw ce;
    } catch (Exception e) {
      throw new AXF_CLS_ContractException(
        'Proveniencia malformada (JSON canonico).'
      );
    }
  }
}
