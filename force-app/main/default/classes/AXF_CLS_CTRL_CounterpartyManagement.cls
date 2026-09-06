/**
 * @description Controller exclusivo para o componente LWC aXF_LWC_counterpartyManagement (AXF-51).
 * Atua como camada fina de orquestração, validação de entrada e normalização de erros.
 * Não contém lógica de negócio reutilizável (PROJECT_RULES.md).
 */
public with sharing class AXF_CLS_CTRL_CounterpartyManagement {

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
   * @description Consulta contrapartes da entidade ativa para listagem e filtro de busca.
   */
  @AuraEnabled(cacheable=true)
  public static List<ALT_CLS_CounterpartyService.CounterpartySummaryDTO> getCounterparties(Id accountId, String searchKey) {
    try {
      if (accountId == null) {
        throw new AuraHandledException('O ID da Entidade é obrigatório.');
      }
      ALT_CLS_CounterpartyService service = new ALT_CLS_CounterpartyService();
      return service.getCounterpartiesForEntity(accountId, searchKey);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Consulta detalhes de uma contraparte e sua relação específica com a entidade ativa.
   */
  @AuraEnabled(cacheable=true)
  public static ALT_CLS_CounterpartyService.CounterpartyDetailDTO getCounterpartyDetail(Id counterpartyId, Id accountId) {
    try {
      if (counterpartyId == null || accountId == null) {
        throw new AuraHandledException('ID da Contraparte e ID da Entidade são obrigatórios.');
      }
      ALT_CLS_CounterpartyService service = new ALT_CLS_CounterpartyService();
      return service.getCounterpartyDetail(counterpartyId, accountId);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * @description Cria ou atualiza a contraparte e sua relação contratual com a entidade.
   */
  @AuraEnabled
  public static ALT_CLS_CounterpartyService.OperationResultDTO saveCounterparty(ALT_CLS_CounterpartyService.CounterpartyInputDTO payload) {
    try {
      if (payload == null) {
        throw new AuraHandledException('Dados da contraparte não foram informados.');
      }
      ALT_CLS_CounterpartyService service = new ALT_CLS_CounterpartyService();
      return service.createOrUpdateCounterpartyAndRelationship(payload);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }
}
