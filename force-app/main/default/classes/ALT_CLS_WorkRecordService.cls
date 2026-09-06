/**
 * @description Servico de dominio para gestao, submissao, aprovacao e apuracao de Registros de Trabalho (AXF-56).
 *
 * Criterios de Aceite:
 * 1. WorkRecord manual ou importado (AC 1):
 *    - Registra Contract, TermVersion, periodo, quantidade, taxa/moeda, fonte e hash SHA-256 unico de evidencia.
 *    - Reimportacao identica nao duplica (identifica pelo EvidenceHash__c ou contrato + periodo + fonte + quantidade).
 * 2. Ciclo de Vida DRAFT -> SUBMITTED -> APPROVED | REJECTED (AC 2):
 *    - Decisao server-side registra ator (User), instante e motivo.
 *    - Somente registros APPROVED entram na apuracao e agenda.
 * 3. Correcao de WorkRecord Aprovado (AC 3):
 *    - Usa reversao e novo registro/versionamento (lookup ReplacedWorkRecord__c, status anterior SUPERSEDED).
 *    - Nao edita evidencia/historico aprovado.
 * 4. Gating de Agenda e Apuracao (AC 4):
 *    - Agenda ou apuracao de modelo HOURLY sem registros aprovados obrigatorios fica bloqueada com explicacao.
 *    - Nao presume horas.
 */
public with sharing class ALT_CLS_WorkRecordService {

  public static final String STATUS_DRAFT = 'DRAFT';
  public static final String STATUS_SUBMITTED = 'SUBMITTED';
  public static final String STATUS_APPROVED = 'APPROVED';
  public static final String STATUS_REJECTED = 'REJECTED';
  public static final String STATUS_SUPERSEDED = 'SUPERSEDED';

  public static final String SOURCE_MANUAL = 'MANUAL';
  public static final String SOURCE_IMPORT = 'CSV_IMPORT';
  public static final String SOURCE_API = 'API';

  public class WorkRecordInputDTO {
    @AuraEnabled public Id workRecordId;
    @AuraEnabled public Id contractId;
    @AuraEnabled public Id termVersionId;
    @AuraEnabled public Date startDate;
    @AuraEnabled public Date endDate;
    @AuraEnabled public Decimal quantity;
    @AuraEnabled public Decimal rate;
    @AuraEnabled public String currencyIsoCode;
    @AuraEnabled public String source;
    @AuraEnabled public String description;
    @AuraEnabled public String externalEvidenceHash;
  }

  public class WorkRecordDetailDTO {
    @AuraEnabled public Id workRecordId;
    @AuraEnabled public String recordNumber;
    @AuraEnabled public Id contractId;
    @AuraEnabled public String contractCode;
    @AuraEnabled public Id termVersionId;
    @AuraEnabled public String termNumber;
    @AuraEnabled public Date startDate;
    @AuraEnabled public Date endDate;
    @AuraEnabled public Decimal quantity;
    @AuraEnabled public Decimal rate;
    @AuraEnabled public String currencyIsoCode;
    @AuraEnabled public Decimal totalAmount;
    @AuraEnabled public String status;
    @AuraEnabled public String source;
    @AuraEnabled public String evidenceHash;
    @AuraEnabled public String description;
    @AuraEnabled public Id decidedById;
    @AuraEnabled public String decidedByName;
    @AuraEnabled public Datetime decidedAt;
    @AuraEnabled public String decisionReason;
    @AuraEnabled public Id replacedWorkRecordId;
    @AuraEnabled public String replacedWorkRecordNumber;
  }

  public class WorkRecordAssessmentDTO {
    @AuraEnabled public Id contractId;
    @AuraEnabled public Date periodStart;
    @AuraEnabled public Date periodEnd;
    @AuraEnabled public Boolean isApprovedAndComplete;
    @AuraEnabled public Decimal totalApprovedQuantity;
    @AuraEnabled public Decimal totalApprovedAmount;
    @AuraEnabled public Integer approvedRecordsCount;
    @AuraEnabled public Integer pendingRecordsCount;
    @AuraEnabled public String blockageReason;
  }

  /**
   * Registra ou importa um WorkRecord, calculando o hash de evidencia deterministico.
   * Impede duplicatas exatas de reimportacao (AC 1).
   */
  public WorkRecordDetailDTO registerWorkRecord(WorkRecordInputDTO input) {
    validateInput(input);

    String computedHash = input.externalEvidenceHash;
    if (String.isBlank(computedHash)) {
      computedHash = computeEvidenceHash(
        input.contractId,
        input.startDate,
        input.endDate,
        input.quantity,
        input.rate,
        input.currencyIsoCode,
        input.source
      );
    }

    // Checa idempotencia / duplicatas por hash de evidencia
    List<AXF_OBJ_WorkRecord__c> existing = [
      SELECT Id, Name, AXF_WR_LKP_Contract__c, AXF_WR_LKP_TermVersion__c, AXF_WR_DAT_StartDate__c,
             AXF_WR_DAT_EndDate__c, AXF_WR_NUM_Quantity__c, AXF_WR_CUR_Rate__c, AXF_WR_TXT_CurrencyIsoCode__c,
             AXF_WR_CUR_TotalAmount__c, AXF_WR_PKL_Status__c, AXF_WR_TXT_Source__c, AXF_WR_EXI_EvidenceHash__c,
             AXF_WR_TXT_Description__c, AXF_WR_LKP_DecidedBy__c, AXF_WR_DT_DecidedAt__c, AXF_WR_TAL_DecisionReason__c,
             AXF_WR_LKP_ReplacedWorkRecord__c
      FROM AXF_OBJ_WorkRecord__c
      WHERE AXF_WR_EXI_EvidenceHash__c = :computedHash
      LIMIT 1
    ];

    if (!existing.isEmpty()) {
      // Reimportacao identica nao duplica: retorna o registro existente (AC 1)
      return getWorkRecordDetail(existing[0].Id);
    }

    // Se estiver editando um rascunho existente
    AXF_OBJ_WorkRecord__c recordToSave;
    if (input.workRecordId != null) {
      AXF_OBJ_WorkRecord__c current = [
        SELECT Id, AXF_WR_PKL_Status__c
        FROM AXF_OBJ_WorkRecord__c
        WHERE Id = :input.workRecordId
        LIMIT 1
      ];
      if (current.AXF_WR_PKL_Status__c != STATUS_DRAFT && current.AXF_WR_PKL_Status__c != STATUS_REJECTED) {
        throw new IllegalArgumentException('Apenas registros em DRAFT ou REJECTED podem ser editados diretamente.');
      }
      recordToSave = new AXF_OBJ_WorkRecord__c(Id = input.workRecordId);
    } else {
      recordToSave = new AXF_OBJ_WorkRecord__c();
      recordToSave.AXF_WR_PKL_Status__c = STATUS_DRAFT;
    }

    recordToSave.AXF_WR_LKP_Contract__c = input.contractId;
    recordToSave.AXF_WR_LKP_TermVersion__c = input.termVersionId;
    recordToSave.AXF_WR_DAT_StartDate__c = input.startDate;
    recordToSave.AXF_WR_DAT_EndDate__c = input.endDate;
    recordToSave.AXF_WR_NUM_Quantity__c = input.quantity;
    recordToSave.AXF_WR_CUR_Rate__c = input.rate;
    recordToSave.AXF_WR_TXT_CurrencyIsoCode__c = input.currencyIsoCode;
    recordToSave.AXF_WR_CUR_TotalAmount__c = (input.quantity * input.rate).setScale(2, System.RoundingMode.HALF_UP);
    recordToSave.AXF_WR_TXT_Source__c = String.isNotBlank(input.source) ? input.source : SOURCE_MANUAL;
    recordToSave.AXF_WR_EXI_EvidenceHash__c = computedHash;
    recordToSave.AXF_WR_TXT_Description__c = input.description;

    upsert recordToSave;

    return getWorkRecordDetail(recordToSave.Id);
  }

  /**
   * Submete um WorkRecord para aprovacao (DRAFT -> SUBMITTED).
   */
  public WorkRecordDetailDTO submitWorkRecord(Id workRecordId) {
    if (workRecordId == null) {
      throw new IllegalArgumentException('WorkRecord ID obrigatorio para submissao.');
    }

    AXF_OBJ_WorkRecord__c record = [
      SELECT Id, AXF_WR_PKL_Status__c, AXF_WR_NUM_Quantity__c, AXF_WR_CUR_Rate__c, AXF_WR_LKP_Contract__c
      FROM AXF_OBJ_WorkRecord__c
      WHERE Id = :workRecordId
      LIMIT 1
    ];

    if (record.AXF_WR_PKL_Status__c != STATUS_DRAFT && record.AXF_WR_PKL_Status__c != STATUS_REJECTED) {
      throw new IllegalArgumentException('Apenas registros em DRAFT ou REJECTED podem ser submetidos para aprovacao.');
    }

    if (record.AXF_WR_NUM_Quantity__c == null || record.AXF_WR_NUM_Quantity__c <= 0) {
      throw new IllegalArgumentException('Nao e permitido submeter registro de trabalho com quantidade nula ou zerada.');
    }

    record.AXF_WR_PKL_Status__c = STATUS_SUBMITTED;
    record.AXF_WR_LKP_DecidedBy__c = null;
    record.AXF_WR_DT_DecidedAt__c = null;
    record.AXF_WR_TAL_DecisionReason__c = null;

    update record;

    return getWorkRecordDetail(record.Id);
  }

  /**
   * Decisao do Revisor: Aprovar ou Rejeitar um registro submetido (AC 2).
   * Registra no servidor o ator (UserInfo), data/hora atual e justificativa.
   */
  public WorkRecordDetailDTO decideWorkRecord(Id workRecordId, Boolean approved, String reason) {
    if (workRecordId == null) {
      throw new IllegalArgumentException('WorkRecord ID obrigatorio para decisao.');
    }
    if (approved == null) {
      throw new IllegalArgumentException('Decisao (aprovado/rejeitado) deve ser informada.');
    }
    if (!approved && String.isBlank(reason)) {
      throw new IllegalArgumentException('Justificativa e obrigatoria para rejeicao de registro de trabalho.');
    }

    AXF_OBJ_WorkRecord__c record = [
      SELECT Id, AXF_WR_PKL_Status__c, AXF_WR_LKP_Contract__c, AXF_WR_NUM_Quantity__c, AXF_WR_CUR_Rate__c
      FROM AXF_OBJ_WorkRecord__c
      WHERE Id = :workRecordId
      LIMIT 1
    ];

    if (record.AXF_WR_PKL_Status__c != STATUS_SUBMITTED) {
      throw new IllegalArgumentException('Apenas registros em status SUBMITTED podem ser avaliados por um revisor.');
    }

    record.AXF_WR_PKL_Status__c = approved ? STATUS_APPROVED : STATUS_REJECTED;
    record.AXF_WR_LKP_DecidedBy__c = UserInfo.getUserId();
    record.AXF_WR_DT_DecidedAt__c = System.now();
    record.AXF_WR_TAL_DecisionReason__c = reason;

    update record;

    return getWorkRecordDetail(record.Id);
  }

  /**
   * Reversao e Correcao de um WorkRecord Aprovado (AC 3):
   * O registro original aprovado e transicionado para SUPERSEDED (sem alterar seus dados historicos).
   * Um novo registro corretivo e criado apontando para o original via AXF_WR_LKP_ReplacedWorkRecord__c.
   */
  public WorkRecordDetailDTO correctApprovedWorkRecord(Id approvedWorkRecordId, WorkRecordInputDTO replacementInput, String correctionReason) {
    if (approvedWorkRecordId == null) {
      throw new IllegalArgumentException('ID do registro aprovado a ser corrigido e obrigatorio.');
    }
    if (String.isBlank(correctionReason)) {
      throw new IllegalArgumentException('Motivo da correcao/substituicao e obrigatorio.');
    }
    validateInput(replacementInput);

    Savepoint sp = Database.setSavepoint();
    try {
      AXF_OBJ_WorkRecord__c original = [
        SELECT Id, AXF_WR_PKL_Status__c, AXF_WR_LKP_Contract__c, AXF_WR_LKP_TermVersion__c,
               AXF_WR_NUM_Quantity__c, AXF_WR_CUR_Rate__c, AXF_WR_CUR_TotalAmount__c,
               AXF_WR_DAT_StartDate__c, AXF_WR_DAT_EndDate__c, AXF_WR_EXI_EvidenceHash__c
        FROM AXF_OBJ_WorkRecord__c
        WHERE Id = :approvedWorkRecordId
        LIMIT 1
      ];

      if (original.AXF_WR_PKL_Status__c != STATUS_APPROVED) {
        throw new IllegalArgumentException('Apenas registros com status APPROVED podem ser corrigidos via reversao/substituicao.');
      }

      // 1. Marca original como SUPERSEDED
      original.AXF_WR_PKL_Status__c = STATUS_SUPERSEDED;
      original.AXF_WR_TAL_DecisionReason__c = 'Substituido por correcao: ' + correctionReason;
      update original;

      // 2. Cria novo registro corretivo em DRAFT (ou SUBMITTED se especificado)
      AXF_OBJ_WorkRecord__c replacement = new AXF_OBJ_WorkRecord__c();
      replacement.AXF_WR_LKP_Contract__c = original.AXF_WR_LKP_Contract__c;
      replacement.AXF_WR_LKP_TermVersion__c = replacementInput.termVersionId != null ? replacementInput.termVersionId : original.AXF_WR_LKP_TermVersion__c;
      replacement.AXF_WR_DAT_StartDate__c = replacementInput.startDate;
      replacement.AXF_WR_DAT_EndDate__c = replacementInput.endDate;
      replacement.AXF_WR_NUM_Quantity__c = replacementInput.quantity;
      replacement.AXF_WR_CUR_Rate__c = replacementInput.rate;
      replacement.AXF_WR_TXT_CurrencyIsoCode__c = replacementInput.currencyIsoCode;
      replacement.AXF_WR_CUR_TotalAmount__c = (replacementInput.quantity * replacementInput.rate).setScale(2, System.RoundingMode.HALF_UP);
      replacement.AXF_WR_TXT_Source__c = String.isNotBlank(replacementInput.source) ? replacementInput.source : SOURCE_MANUAL;
      replacement.AXF_WR_PKL_Status__c = STATUS_DRAFT;
      replacement.AXF_WR_LKP_ReplacedWorkRecord__c = original.Id;
      replacement.AXF_WR_TXT_Description__c = replacementInput.description;
      replacement.AXF_WR_TAL_DecisionReason__c = 'Registro corretivo originado da substituicao de ' + original.Id + '. Motivo: ' + correctionReason;

      // Gera novo hash distinguindo pelo identificador unico de correcao
      replacement.AXF_WR_EXI_EvidenceHash__c = computeEvidenceHash(
        replacement.AXF_WR_LKP_Contract__c,
        replacement.AXF_WR_DAT_StartDate__c,
        replacement.AXF_WR_DAT_EndDate__c,
        replacement.AXF_WR_NUM_Quantity__c,
        replacement.AXF_WR_CUR_Rate__c,
        replacement.AXF_WR_TXT_CurrencyIsoCode__c,
        'CORRECTION_' + String.valueOf(System.currentTimeMillis())
      );

      insert replacement;

      return getWorkRecordDetail(replacement.Id);
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }
  }

  /**
   * Avalia a apuracao de horas/quantidades para um determinado periodo de contrato (AC 4).
   * Se houver modelo HOURLY sem registros obrigatorios APPROVED, bloqueia a publicacao com explicacao.
   */
  public WorkRecordAssessmentDTO assessContractWorkRecords(Id contractId, Date periodStart, Date periodEnd) {
    if (contractId == null) {
      throw new IllegalArgumentException('ID do contrato e obrigatorio.');
    }

    WorkRecordAssessmentDTO dto = new WorkRecordAssessmentDTO();
    dto.contractId = contractId;
    dto.periodStart = periodStart;
    dto.periodEnd = periodEnd;
    dto.totalApprovedQuantity = 0;
    dto.totalApprovedAmount = 0;
    dto.approvedRecordsCount = 0;
    dto.pendingRecordsCount = 0;

    List<AXF_OBJ_WorkRecord__c> records = [
      SELECT Id, AXF_WR_PKL_Status__c, AXF_WR_NUM_Quantity__c, AXF_WR_CUR_TotalAmount__c,
             AXF_WR_DAT_StartDate__c, AXF_WR_DAT_EndDate__c
      FROM AXF_OBJ_WorkRecord__c
      WHERE AXF_WR_LKP_Contract__c = :contractId
        AND AXF_WR_DAT_StartDate__c >= :periodStart
        AND AXF_WR_DAT_EndDate__c <= :periodEnd
    ];

    for (AXF_OBJ_WorkRecord__c wr : records) {
      if (wr.AXF_WR_PKL_Status__c == STATUS_APPROVED) {
        dto.totalApprovedQuantity += (wr.AXF_WR_NUM_Quantity__c != null ? wr.AXF_WR_NUM_Quantity__c : 0);
        dto.totalApprovedAmount += (wr.AXF_WR_CUR_TotalAmount__c != null ? wr.AXF_WR_CUR_TotalAmount__c : 0);
        dto.approvedRecordsCount++;
      } else if (wr.AXF_WR_PKL_Status__c == STATUS_SUBMITTED || wr.AXF_WR_PKL_Status__c == STATUS_DRAFT) {
        dto.pendingRecordsCount++;
      }
    }

    if (dto.approvedRecordsCount == 0 && dto.pendingRecordsCount == 0) {
      dto.isApprovedAndComplete = false;
      dto.blockageReason = 'Nao ha registros de trabalho com status APPROVED para o periodo informado (' + periodStart.format() + ' a ' + periodEnd.format() + '). A publicacao de agenda com remuneracao por horas/quantidade exige comprovacao previa (AXF-56 AC 4).';
    } else if (dto.pendingRecordsCount > 0) {
      dto.isApprovedAndComplete = false;
      dto.blockageReason = 'Existem ' + dto.pendingRecordsCount + ' registros de trabalho pendentes de revisao/aprovacao no periodo. Conclua a aprovacao antes de publicar a apuracao final (AXF-56 AC 4).';
    } else if (dto.approvedRecordsCount == 0) {
      dto.isApprovedAndComplete = false;
      dto.blockageReason = 'Nao ha registros de trabalho com status APPROVED para o periodo informado (' + periodStart.format() + ' a ' + periodEnd.format() + ').';
    } else {
      dto.isApprovedAndComplete = true;
      dto.blockageReason = null;
    }

    return dto;
  }

  /**
   * Retorna os registros de trabalho de um contrato.
   */
  public List<WorkRecordDetailDTO> getWorkRecordsByContract(Id contractId) {
    if (contractId == null) {
      return new List<WorkRecordDetailDTO>();
    }

    List<AXF_OBJ_WorkRecord__c> records = [
      SELECT Id, Name, AXF_WR_LKP_Contract__c, AXF_WR_LKP_Contract__r.Name,
             AXF_WR_LKP_TermVersion__c, AXF_WR_LKP_TermVersion__r.Name,
             AXF_WR_DAT_StartDate__c, AXF_WR_DAT_EndDate__c, AXF_WR_NUM_Quantity__c,
             AXF_WR_CUR_Rate__c, AXF_WR_TXT_CurrencyIsoCode__c, AXF_WR_CUR_TotalAmount__c,
             AXF_WR_PKL_Status__c, AXF_WR_TXT_Source__c, AXF_WR_EXI_EvidenceHash__c,
             AXF_WR_TXT_Description__c, AXF_WR_LKP_DecidedBy__c, AXF_WR_LKP_DecidedBy__r.Name,
             AXF_WR_DT_DecidedAt__c, AXF_WR_TAL_DecisionReason__c,
             AXF_WR_LKP_ReplacedWorkRecord__c, AXF_WR_LKP_ReplacedWorkRecord__r.Name
      FROM AXF_OBJ_WorkRecord__c
      WHERE AXF_WR_LKP_Contract__c = :contractId
      ORDER BY AXF_WR_DAT_StartDate__c DESC, CreatedDate DESC
    ];

    List<WorkRecordDetailDTO> results = new List<WorkRecordDetailDTO>();
    for (AXF_OBJ_WorkRecord__c wr : records) {
      results.add(mapToDetailDTO(wr));
    }
    return results;
  }

  public WorkRecordDetailDTO getWorkRecordDetail(Id workRecordId) {
    List<AXF_OBJ_WorkRecord__c> records = [
      SELECT Id, Name, AXF_WR_LKP_Contract__c, AXF_WR_LKP_Contract__r.Name,
             AXF_WR_LKP_TermVersion__c, AXF_WR_LKP_TermVersion__r.Name,
             AXF_WR_DAT_StartDate__c, AXF_WR_DAT_EndDate__c, AXF_WR_NUM_Quantity__c,
             AXF_WR_CUR_Rate__c, AXF_WR_TXT_CurrencyIsoCode__c, AXF_WR_CUR_TotalAmount__c,
             AXF_WR_PKL_Status__c, AXF_WR_TXT_Source__c, AXF_WR_EXI_EvidenceHash__c,
             AXF_WR_TXT_Description__c, AXF_WR_LKP_DecidedBy__c, AXF_WR_LKP_DecidedBy__r.Name,
             AXF_WR_DT_DecidedAt__c, AXF_WR_TAL_DecisionReason__c,
             AXF_WR_LKP_ReplacedWorkRecord__c, AXF_WR_LKP_ReplacedWorkRecord__r.Name
      FROM AXF_OBJ_WorkRecord__c
      WHERE Id = :workRecordId
      LIMIT 1
    ];
    if (records.isEmpty()) {
      return null;
    }
    return mapToDetailDTO(records[0]);
  }

  public static String computeEvidenceHash(
    Id contractId,
    Date startDate,
    Date endDate,
    Decimal quantity,
    Decimal rate,
    String currencyIsoCode,
    String source
  ) {
    String payload = String.valueOf(contractId) + '|' +
      String.valueOf(startDate) + '|' +
      String.valueOf(endDate) + '|' +
      String.valueOf(quantity != null ? quantity.setScale(2) : 0) + '|' +
      String.valueOf(rate != null ? rate.setScale(2) : 0) + '|' +
      String.valueOf(currencyIsoCode) + '|' +
      String.valueOf(source);

    Blob hashBlob = Crypto.generateDigest('SHA-256', Blob.valueOf(payload));
    return EncodingUtil.convertToHex(hashBlob);
  }

  private void validateInput(WorkRecordInputDTO input) {
    if (input == null) {
      throw new IllegalArgumentException('Dados do registro de trabalho sao obrigatorios.');
    }
    if (input.contractId == null) {
      throw new IllegalArgumentException('Contrato vinculado e obrigatorio.');
    }
    if (input.startDate == null || input.endDate == null) {
      throw new IllegalArgumentException('Periodo (Data de Inicio e Fim) e obrigatorio.');
    }
    if (input.startDate > input.endDate) {
      throw new IllegalArgumentException('Data de inicio nao pode ser posterior a data de fim.');
    }
    if (input.quantity == null || input.quantity <= 0) {
      throw new IllegalArgumentException('Quantidade de horas/trabalho deve ser maior que zero.');
    }
    if (input.rate == null || input.rate < 0) {
      throw new IllegalArgumentException('Taxa unitaria nao pode ser negativa.');
    }
    if (String.isBlank(input.currencyIsoCode)) {
      throw new IllegalArgumentException('Moeda (CurrencyIsoCode) e obrigatoria.');
    }
  }

  private WorkRecordDetailDTO mapToDetailDTO(AXF_OBJ_WorkRecord__c wr) {
    WorkRecordDetailDTO dto = new WorkRecordDetailDTO();
    dto.workRecordId = wr.Id;
    dto.recordNumber = wr.Name;
    dto.contractId = wr.AXF_WR_LKP_Contract__c;
    dto.contractCode = wr.AXF_WR_LKP_Contract__r != null ? wr.AXF_WR_LKP_Contract__r.Name : null;
    dto.termVersionId = wr.AXF_WR_LKP_TermVersion__c;
    dto.termNumber = wr.AXF_WR_LKP_TermVersion__r != null ? wr.AXF_WR_LKP_TermVersion__r.Name : null;
    dto.startDate = wr.AXF_WR_DAT_StartDate__c;
    dto.endDate = wr.AXF_WR_DAT_EndDate__c;
    dto.quantity = wr.AXF_WR_NUM_Quantity__c;
    dto.rate = wr.AXF_WR_CUR_Rate__c;
    dto.currencyIsoCode = wr.AXF_WR_TXT_CurrencyIsoCode__c;
    dto.totalAmount = wr.AXF_WR_CUR_TotalAmount__c;
    dto.status = wr.AXF_WR_PKL_Status__c;
    dto.source = wr.AXF_WR_TXT_Source__c;
    dto.evidenceHash = wr.AXF_WR_EXI_EvidenceHash__c;
    dto.description = wr.AXF_WR_TXT_Description__c;
    dto.decidedById = wr.AXF_WR_LKP_DecidedBy__c;
    dto.decidedByName = wr.AXF_WR_LKP_DecidedBy__r != null ? wr.AXF_WR_LKP_DecidedBy__r.Name : null;
    dto.decidedAt = wr.AXF_WR_DT_DecidedAt__c;
    dto.decisionReason = wr.AXF_WR_TAL_DecisionReason__c;
    dto.replacedWorkRecordId = wr.AXF_WR_LKP_ReplacedWorkRecord__c;
    dto.replacedWorkRecordNumber = wr.AXF_WR_LKP_ReplacedWorkRecord__r != null ? wr.AXF_WR_LKP_ReplacedWorkRecord__r.Name : null;
    return dto;
  }
}
