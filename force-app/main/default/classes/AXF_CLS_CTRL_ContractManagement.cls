/**
 * @description Controller exclusivo para o componente LWC aXF_LWC_contractManagement (AXF-52).
 * Atua como camada fina de orquestração, validação de entrada e normalização de erros.
 * Não contém lógica de negócio reutilizável (PROJECT_RULES.md).
 */
public with sharing class AXF_CLS_CTRL_ContractManagement {

  /**
   * @description Consulta as entidades autorizadas (Accounts) disponíveis para o usuário.
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
   * @description Consulta as relações contratuais ativas para a entidade informada.
   */
  @AuraEnabled(cacheable=true)
  public static List<ALT_CLS_ContractService.ActiveRelationshipDTO> getActiveRelationships(Id accountId) {
    try {
      if (accountId == null) {
        throw new AuraHandledException('O ID da Entidade é obrigatório.');
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
        throw new AuraHandledException('O ID da Entidade é obrigatório.');
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
        throw new AuraHandledException('ID do Contrato e ID da Entidade são obrigatórios.');
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
        throw new AuraHandledException('Dados do contrato não foram informados.');
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
        throw new AuraHandledException('Dados do contrato não foram informados.');
      }
      ALT_CLS_ContractService service = new ALT_CLS_ContractService();
      return service.updateDraftContract(payload);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }
}
