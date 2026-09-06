/**
 * @description Controller exclusivo para o componente LWC aXF_LWC_contractManagement (AXF-52, AXF-54).
 * Atua como camada fina de orquestracao, validacao de entrada e normalizacao de erros.
 * Nao contem logica de negocio reutilizavel (PROJECT_RULES.md).
 */
public with sharing class AXF_CLS_CTRL_ContractManagement {

  /**
   * @description Consulta as entidades autorizadas (Accounts) disponiveis para o usuario.
   */
  @AuraEnabled(cacheable=true)
  public static List<AXF_CLS_AuthorizedContextService.ContextView> getAuthorizedEntities() {
    try {
      return AXF_CLS_AuthorizedContextService.listAuthorizedContexts();
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Consulta as relacoes contratuais ativas para a entidade informada.
   */
  @AuraEnabled(cacheable=true)
  public static List<ALT_CLS_ContractService.ActiveRelationshipDTO> getActiveRelationships(Id accountId) {
    try {
      if (accountId == null) {
        throw new AuraHandledException('O ID da Entidade e obrigatorio.');
      }
      ALT_CLS_ContractService service = new ALT_CLS_ContractService();
      return service.getActiveRelationships(accountId);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Consulta contratos da entidade selecionada.
   */
  @AuraEnabled(cacheable=true)
  public static List<ALT_CLS_ContractService.ContractSummaryDTO> getContracts(Id accountId) {
    try {
      if (accountId == null) {
        throw new AuraHandledException('O ID da Entidade e obrigatorio.');
      }
      ALT_CLS_ContractService service = new ALT_CLS_ContractService();
      return service.getContractsByAccount(accountId);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Consulta detalhada de um contrato.
   */
  @AuraEnabled(cacheable=true)
  public static ALT_CLS_ContractService.ContractDetailDTO getContractDetail(Id contractId, Id accountId) {
    try {
      if (contractId == null || accountId == null) {
        throw new AuraHandledException('ID do Contrato e ID da Entidade sao obrigatorios.');
      }
      ALT_CLS_ContractService service = new ALT_CLS_ContractService();
      return service.getContractDetail(contractId, accountId);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Cria um novo contrato em rascunho (DRAFT).
   */
  @AuraEnabled
  public static ALT_CLS_ContractService.OperationResultDTO createDraftContract(ALT_CLS_ContractService.ContractInputDTO payload) {
    try {
      if (payload == null) {
        throw new AuraHandledException('Dados do contrato nao foram informados.');
      }
      ALT_CLS_ContractService service = new ALT_CLS_ContractService();
      return service.createDraftContract(payload);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Atualiza dados de um contrato em rascunho (DRAFT).
   */
  @AuraEnabled
  public static ALT_CLS_ContractService.OperationResultDTO updateDraftContract(ALT_CLS_ContractService.ContractInputDTO payload) {
    try {
      if (payload == null) {
        throw new AuraHandledException('Dados do contrato nao foram informados.');
      }
      ALT_CLS_ContractService service = new ALT_CLS_ContractService();
      return service.updateDraftContract(payload);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Consulta as versoes de termos de um contrato (AXF-54).
   */
  @AuraEnabled(cacheable=true)
  public static List<ALT_CLS_ContractRemunerationService.TermVersionDetailDTO> getTermVersions(Id contractId, Id accountId) {
    try {
      if (contractId == null) {
        throw new AuraHandledException('ID do Contrato e obrigatorio.');
      }
      ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();
      return service.getTermVersionsByContract(contractId, accountId);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Cria ou atualiza uma versao de termo em rascunho (AXF-54).
   */
  @AuraEnabled
  public static ALT_CLS_ContractRemunerationService.OperationResultDTO saveDraftTermVersion(ALT_CLS_ContractRemunerationService.TermVersionInputDTO payload) {
    try {
      if (payload == null) {
        throw new AuraHandledException('Dados da versao do termo nao informados.');
      }
      ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();
      return service.saveDraftTermVersion(payload);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Calcula o preview do cronograma financeiro e residual canonico (AXF-54, GF-04).
   */
  @AuraEnabled
  public static ALT_CLS_ContractRemunerationService.ScheduleCalculationResultDTO calculateSchedulePreview(ALT_CLS_ContractRemunerationService.TermVersionInputDTO payload) {
    try {
      if (payload == null) {
        throw new AuraHandledException('Dados para calculo do cronograma nao informados.');
      }
      ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();
      return service.calculateSchedule(payload);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Consulta dados de revisao formal de uma versao de termo (AXF-53, AC 1).
   */
  @AuraEnabled(cacheable=true)
  public static ALT_CLS_ContractRemunerationService.TermVersionReviewDTO getTermVersionReview(Id termVersionId, Id accountId) {
    try {
      if (termVersionId == null) {
        throw new AuraHandledException('ID da versao de termo e obrigatorio.');
      }
      ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();
      return service.getTermVersionReview(termVersionId, accountId);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Tenta ativar uma versao de termo contratual com validacao de concorrencia e retroatividade (AXF-54, AXF-53).
   */
  @AuraEnabled
  public static ALT_CLS_ContractRemunerationService.OperationResultDTO activateTermVersion(Id termVersionId, Id accountId, Long expectedContractVersion, Long expectedTermVersion) {
    try {
      if (termVersionId == null) {
        throw new AuraHandledException('ID da versao de termo e obrigatorio.');
      }
      ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();
      return service.activateTermVersion(termVersionId, accountId, expectedContractVersion, expectedTermVersion);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Consulta os registros de trabalho vinculados a um contrato (AXF-56).
   */
  @AuraEnabled(cacheable=true)
  public static List<ALT_CLS_WorkRecordService.WorkRecordDetailDTO> getWorkRecords(Id contractId) {
    try {
      if (contractId == null) {
        throw new AuraHandledException('ID do Contrato e obrigatorio.');
      }
      ALT_CLS_WorkRecordService service = new ALT_CLS_WorkRecordService();
      return service.getWorkRecordsByContract(contractId);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Registra ou importa um novo registro de trabalho (AXF-56).
   */
  @AuraEnabled
  public static ALT_CLS_WorkRecordService.WorkRecordDetailDTO registerWorkRecord(ALT_CLS_WorkRecordService.WorkRecordInputDTO payload) {
    try {
      if (payload == null) {
        throw new AuraHandledException('Dados do registro de trabalho nao foram informados.');
      }
      ALT_CLS_WorkRecordService service = new ALT_CLS_WorkRecordService();
      return service.registerWorkRecord(payload);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Submete um registro de trabalho para aprovacao (DRAFT -> SUBMITTED) (AXF-56).
   */
  @AuraEnabled
  public static ALT_CLS_WorkRecordService.WorkRecordDetailDTO submitWorkRecord(Id workRecordId) {
    try {
      if (workRecordId == null) {
        throw new AuraHandledException('ID do registro de trabalho e obrigatorio.');
      }
      ALT_CLS_WorkRecordService service = new ALT_CLS_WorkRecordService();
      return service.submitWorkRecord(workRecordId);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Avalia e decide (aprova ou rejeita) um registro de trabalho submetido (AXF-56).
   */
  @AuraEnabled
  public static ALT_CLS_WorkRecordService.WorkRecordDetailDTO decideWorkRecord(Id workRecordId, Boolean approved, String reason) {
    try {
      if (workRecordId == null) {
        throw new AuraHandledException('ID do registro de trabalho e obrigatorio.');
      }
      ALT_CLS_WorkRecordService service = new ALT_CLS_WorkRecordService();
      return service.decideWorkRecord(workRecordId, approved, reason);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Corrige um registro de trabalho aprovado atraves de reversao e substituicao (AXF-56).
   */
  @AuraEnabled
  public static ALT_CLS_WorkRecordService.WorkRecordDetailDTO correctApprovedWorkRecord(Id approvedWorkRecordId, ALT_CLS_WorkRecordService.WorkRecordInputDTO replacementPayload, String correctionReason) {
    try {
      if (approvedWorkRecordId == null) {
        throw new AuraHandledException('ID do registro aprovado e obrigatorio.');
      }
      ALT_CLS_WorkRecordService service = new ALT_CLS_WorkRecordService();
      return service.correctApprovedWorkRecord(approvedWorkRecordId, replacementPayload, correctionReason);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Avalia se as horas/quantidades de um periodo estao aprovadas e completas (AXF-56 AC 4).
   */
  @AuraEnabled(cacheable=true)
  public static ALT_CLS_WorkRecordService.WorkRecordAssessmentDTO assessContractWorkRecords(Id contractId, Date periodStart, Date periodEnd) {
    try {
      if (contractId == null) {
        throw new AuraHandledException('ID do Contrato e obrigatorio.');
      }
      ALT_CLS_WorkRecordService service = new ALT_CLS_WorkRecordService();
      return service.assessContractWorkRecords(contractId, periodStart, periodEnd);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }
}
