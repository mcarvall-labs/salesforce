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
  public static List<ALT_CLS_CounterpartyService.CounterpartySummaryDTO> getCounterparties(
    Id accountId,
    String searchKey
  ) {
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
  public static ALT_CLS_CounterpartyService.CounterpartyDetailDTO getCounterpartyDetail(
    Id counterpartyId,
    Id accountId
  ) {
    try {
      if (counterpartyId == null || accountId == null) {
        throw new AuraHandledException(
          'ID da Contraparte e ID da Entidade são obrigatórios.'
        );
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
  // Primitive params (not the service's inner DTO) so the LWC call binds reliably:
  // Aura does not populate the fields of an @AuraEnabled Apex class that is an inner
  // class of another top-level class (same limitation fixed in
  // AXF_CLS_CTRL_OnboardingProgress). AXF-51 / AXF-106.
  @AuraEnabled
  public static ALT_CLS_CounterpartyService.OperationResultDTO saveCounterparty(
    Id counterpartyId,
    Id accountId,
    String legalName,
    String displayName,
    String kind,
    String country,
    String status,
    Long version,
    Id relationshipId,
    String role,
    String relationshipStatus,
    String entitySpecificDisplay,
    Date validFrom,
    Date validTo,
    String addressSnapshot,
    String email,
    String phone,
    String contactName,
    Long relationshipVersion,
    String taxScheme,
    String taxCountry,
    String taxRawDocument
  ) {
    try {
      ALT_CLS_CounterpartyService.CounterpartyInputDTO payload = new ALT_CLS_CounterpartyService.CounterpartyInputDTO();
      payload.counterpartyId = counterpartyId;
      payload.accountId = accountId;
      payload.legalName = legalName;
      payload.displayName = displayName;
      payload.kind = kind;
      payload.country = country;
      payload.status = status;
      payload.version = version;
      payload.relationshipId = relationshipId;
      payload.role = role;
      payload.relationshipStatus = relationshipStatus;
      payload.entitySpecificDisplay = entitySpecificDisplay;
      payload.validFrom = validFrom;
      payload.validTo = validTo;
      payload.addressSnapshot = addressSnapshot;
      payload.email = email;
      payload.phone = phone;
      payload.contactName = contactName;
      payload.relationshipVersion = relationshipVersion;
      payload.taxScheme = taxScheme;
      payload.taxCountry = taxCountry;
      payload.taxRawDocument = taxRawDocument;
      ALT_CLS_CounterpartyService service = new ALT_CLS_CounterpartyService();
      return service.createOrUpdateCounterpartyAndRelationship(payload);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }
}
