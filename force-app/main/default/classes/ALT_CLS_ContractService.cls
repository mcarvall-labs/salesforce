/**
 * @description Serviço de domínio para gestão de Contratos em Rascunho (AXF-52).
 *
 * Princípios e Contratos:
 * - Root privado AXF_OBJ_Contract__c referenciando Entidade (Account) e Relação com Contraparte (CER) (G1, AD-14).
 * - Código de contrato canônico único por Entidade via AXF_CLS_IdentityFraming (G6).
 * - Rejeição estrita de relações inativas ou pertencentes a outra entidade (cross-entity isolation).
 * - Mutação de rascunho (DRAFT) com expectedVersion (concorrência otimista) e chave de idempotência (G6).
 * - Bloqueio estrito de operações de cancelamento, término ou substituição enquanto não houver operação canônica (AC 3).
 * - Garantia estrita de que nenhum CashFlow / FinancialTransaction ou documento é criado no cadastro de contratos.
 * - Compartilhamento derivado por relação via Apex Managed Sharing (RowCause AXF_ContractAccess__c).
 */
public with sharing class ALT_CLS_ContractService {

  public static final String SHARING_ROW_CAUSE = 'AXF_ContractAccess__c';

  public class ContractInputDTO {
    @AuraEnabled public Id contractId;
    @AuraEnabled public Id accountId;
    @AuraEnabled public Id counterpartyId;
    @AuraEnabled public Id relationshipId;
    @AuraEnabled public String contractCode;
    @AuraEnabled public String title;
    @AuraEnabled public String lifecycle;
    @AuraEnabled public String contractType;
    @AuraEnabled public String currencyIsoCode;
    @AuraEnabled public Date startDate;
    @AuraEnabled public Date endDate;
    @AuraEnabled public String description;
    @AuraEnabled public Long version;
    @AuraEnabled public String clientRequestId;
  }

  public class ContractSummaryDTO {
    @AuraEnabled public Id contractId;
    @AuraEnabled public String contractNumber;
    @AuraEnabled public String contractCode;
    @AuraEnabled public String title;
    @AuraEnabled public String lifecycle;
    @AuraEnabled public String contractType;
    @AuraEnabled public String currencyIsoCode;
    @AuraEnabled public Id accountId;
    @AuraEnabled public String accountName;
    @AuraEnabled public Id counterpartyId;
    @AuraEnabled public String counterpartyName;
    @AuraEnabled public Id relationshipId;
    @AuraEnabled public String relationshipRole;
    @AuraEnabled public Date startDate;
    @AuraEnabled public Date endDate;
    @AuraEnabled public Long version;
  }

  public class ContractDetailDTO {
    @AuraEnabled public Id contractId;
    @AuraEnabled public String contractNumber;
    @AuraEnabled public String contractCode;
    @AuraEnabled public String title;
    @AuraEnabled public String lifecycle;
    @AuraEnabled public String contractType;
    @AuraEnabled public String currencyIsoCode;
    @AuraEnabled public Id accountId;
    @AuraEnabled public String accountName;
    @AuraEnabled public Id counterpartyId;
    @AuraEnabled public String counterpartyName;
    @AuraEnabled public Id relationshipId;
    @AuraEnabled public String relationshipRole;
    @AuraEnabled public Date startDate;
    @AuraEnabled public Date endDate;
    @AuraEnabled public Date terminationEffectiveDate;
    @AuraEnabled public String description;
    @AuraEnabled public String contractKey;
    @AuraEnabled public String clientRequestId;
    @AuraEnabled public Long version;
    @AuraEnabled public Id predecessorContractId;
    @AuraEnabled public Id successorContractId;
    @AuraEnabled public Datetime createdDate;
    @AuraEnabled public Datetime lastModifiedDate;
  }

  public class OperationResultDTO {
    @AuraEnabled public Boolean success;
    @AuraEnabled public String message;
    @AuraEnabled public Id contractId;
    @AuraEnabled public Long version;
  }

  public class ActiveRelationshipDTO {
    @AuraEnabled public Id relationshipId;
    @AuraEnabled public Id counterpartyId;
    @AuraEnabled public String counterpartyName;
    @AuraEnabled public String role;
    @AuraEnabled public String status;
    @AuraEnabled public String entitySpecificDisplay;
  }

  /**
   * @description Gera a chave canônica determinística do contrato (G6).
   */
  public static String buildContractKey(Id accountId, String contractCode) {
    if (accountId == null || String.isBlank(contractCode)) {
      throw new AXF_CLS_ContractException('Entidade e Código do contrato são obrigatórios para chave canônica.');
    }
    return AXF_CLS_IdentityFraming.key(new List<Object>{
      'CONTRACT',
      accountId,
      contractCode.trim().toUpperCase()
    });
  }

  /**
   * @description Lista contratos de uma Entidade titular (Account).
   */
  public List<ContractSummaryDTO> getContractsByAccount(Id accountId) {
    if (accountId == null) {
      throw new AXF_CLS_ContractException('ID da Entidade titular é obrigatório.');
    }

    validateAccountAccess(accountId);

    List<AXF_OBJ_Contract__c> contracts = [
      SELECT
        Id,
        Name,
        AXF_CTR_TXT_ContractCode__c,
        AXF_CTR_TXT_Title__c,
        AXF_CTR_PKL_Lifecycle__c,
        AXF_CTR_PKL_Type__c,
        AXF_CTR_TXT_CurrencyIsoCode__c,
        AXF_CTR_LKP_Account__c,
        AXF_CTR_LKP_Account__r.Name,
        AXF_CTR_LKP_Counterparty__c,
        AXF_CTR_LKP_Counterparty__r.AXF_CPTY_TXT_DisplayName__c,
        AXF_CTR_LKP_Relationship__c,
        AXF_CTR_LKP_Relationship__r.AXF_CER_PKL_Role__c,
        AXF_CTR_DAT_StartDate__c,
        AXF_CTR_DAT_EndDate__c,
        AXF_CTR_NUM_Version__c
      FROM AXF_OBJ_Contract__c
      WHERE AXF_CTR_LKP_Account__c = :accountId
      ORDER BY CreatedDate DESC
    ];

    List<ContractSummaryDTO> summaries = new List<ContractSummaryDTO>();
    for (AXF_OBJ_Contract__c c : contracts) {
      ContractSummaryDTO dto = new ContractSummaryDTO();
      dto.contractId = c.Id;
      dto.contractNumber = c.Name;
      dto.contractCode = c.AXF_CTR_TXT_ContractCode__c;
      dto.title = c.AXF_CTR_TXT_Title__c;
      dto.lifecycle = c.AXF_CTR_PKL_Lifecycle__c;
      dto.contractType = c.AXF_CTR_PKL_Type__c;
      dto.currencyIsoCode = c.AXF_CTR_TXT_CurrencyIsoCode__c;
      dto.accountId = c.AXF_CTR_LKP_Account__c;
      dto.accountName = c.AXF_CTR_LKP_Account__r.Name;
      dto.counterpartyId = c.AXF_CTR_LKP_Counterparty__c;
      dto.counterpartyName = c.AXF_CTR_LKP_Counterparty__r.AXF_CPTY_TXT_DisplayName__c;
      dto.relationshipId = c.AXF_CTR_LKP_Relationship__c;
      dto.relationshipRole = c.AXF_CTR_LKP_Relationship__r.AXF_CER_PKL_Role__c;
      dto.startDate = c.AXF_CTR_DAT_StartDate__c;
      dto.endDate = c.AXF_CTR_DAT_EndDate__c;
      dto.version = (c.AXF_CTR_NUM_Version__c != null) ? c.AXF_CTR_NUM_Version__c.longValue() : 1;
      summaries.add(dto);
    }
    return summaries;
  }

  /**
   * @description Consulta detalhada de um contrato.
   */
  public ContractDetailDTO getContractDetail(Id contractId, Id accountId) {
    if (contractId == null || accountId == null) {
      throw new AXF_CLS_ContractException('ID do Contrato e ID da Entidade são obrigatórios.');
    }

    validateAccountAccess(accountId);

    List<AXF_OBJ_Contract__c> contracts = [
      SELECT
        Id,
        Name,
        AXF_CTR_TXT_ContractCode__c,
        AXF_CTR_EXI_ContractKey__c,
        AXF_CTR_TXT_Title__c,
        AXF_CTR_PKL_Lifecycle__c,
        AXF_CTR_PKL_Type__c,
        AXF_CTR_TXT_CurrencyIsoCode__c,
        AXF_CTR_LKP_Account__c,
        AXF_CTR_LKP_Account__r.Name,
        AXF_CTR_LKP_Counterparty__c,
        AXF_CTR_LKP_Counterparty__r.AXF_CPTY_TXT_DisplayName__c,
        AXF_CTR_LKP_Relationship__c,
        AXF_CTR_LKP_Relationship__r.AXF_CER_PKL_Role__c,
        AXF_CTR_DAT_StartDate__c,
        AXF_CTR_DAT_EndDate__c,
        AXF_CTR_DAT_TerminationEffectiveDate__c,
        AXF_CTR_TAL_Description__c,
        AXF_CTR_EXI_ClientRequestId__c,
        AXF_CTR_NUM_Version__c,
        AXF_CTR_LKP_PredecessorContract__c,
        AXF_CTR_LKP_SuccessorContract__c,
        CreatedDate,
        LastModifiedDate
      FROM AXF_OBJ_Contract__c
      WHERE Id = :contractId
        AND AXF_CTR_LKP_Account__c = :accountId
      LIMIT 1
    ];

    if (contracts.isEmpty()) {
      throw new AXF_CLS_ContractException('Contrato não encontrado ou não pertence à Entidade informada.');
    }

    AXF_OBJ_Contract__c c = contracts[0];
    ContractDetailDTO dto = new ContractDetailDTO();
    dto.contractId = c.Id;
    dto.contractNumber = c.Name;
    dto.contractCode = c.AXF_CTR_TXT_ContractCode__c;
    dto.contractKey = c.AXF_CTR_EXI_ContractKey__c;
    dto.title = c.AXF_CTR_TXT_Title__c;
    dto.lifecycle = c.AXF_CTR_PKL_Lifecycle__c;
    dto.contractType = c.AXF_CTR_PKL_Type__c;
    dto.currencyIsoCode = c.AXF_CTR_TXT_CurrencyIsoCode__c;
    dto.accountId = c.AXF_CTR_LKP_Account__c;
    dto.accountName = c.AXF_CTR_LKP_Account__r.Name;
    dto.counterpartyId = c.AXF_CTR_LKP_Counterparty__c;
    dto.counterpartyName = c.AXF_CTR_LKP_Counterparty__r.AXF_CPTY_TXT_DisplayName__c;
    dto.relationshipId = c.AXF_CTR_LKP_Relationship__c;
    dto.relationshipRole = c.AXF_CTR_LKP_Relationship__r.AXF_CER_PKL_Role__c;
    dto.startDate = c.AXF_CTR_DAT_StartDate__c;
    dto.endDate = c.AXF_CTR_DAT_EndDate__c;
    dto.terminationEffectiveDate = c.AXF_CTR_DAT_TerminationEffectiveDate__c;
    dto.description = c.AXF_CTR_TAL_Description__c;
    dto.clientRequestId = c.AXF_CTR_EXI_ClientRequestId__c;
    dto.version = (c.AXF_CTR_NUM_Version__c != null) ? c.AXF_CTR_NUM_Version__c.longValue() : 1;
    dto.predecessorContractId = c.AXF_CTR_LKP_PredecessorContract__c;
    dto.successorContractId = c.AXF_CTR_LKP_SuccessorContract__c;
    dto.createdDate = c.CreatedDate;
    dto.lastModifiedDate = c.LastModifiedDate;

    return dto;
  }

  /**
   * @description Lista relações ativas da Entidade para preenchimento no formulário de Contrato.
   */
  public List<ActiveRelationshipDTO> getActiveRelationships(Id accountId) {
    if (accountId == null) {
      throw new AXF_CLS_ContractException('ID da Entidade é obrigatório.');
    }

    validateAccountAccess(accountId);

    List<AXF_OBJ_CounterpartyEntityRelationship__c> relationships = [
      SELECT
        Id,
        AXF_CER_LKP_Counterparty__c,
        AXF_CER_LKP_Counterparty__r.AXF_CPTY_TXT_DisplayName__c,
        AXF_CER_PKL_Role__c,
        AXF_CER_PKL_Status__c,
        AXF_CER_TXT_EntitySpecificDisplay__c
      FROM AXF_OBJ_CounterpartyEntityRelationship__c
      WHERE AXF_CER_LKP_Account__c = :accountId
        AND AXF_CER_PKL_Status__c = 'ACTIVE'
      ORDER BY AXF_CER_LKP_Counterparty__r.AXF_CPTY_TXT_DisplayName__c ASC
    ];

    List<ActiveRelationshipDTO> result = new List<ActiveRelationshipDTO>();
    for (AXF_OBJ_CounterpartyEntityRelationship__c rel : relationships) {
      ActiveRelationshipDTO dto = new ActiveRelationshipDTO();
      dto.relationshipId = rel.Id;
      dto.counterpartyId = rel.AXF_CER_LKP_Counterparty__c;
      dto.counterpartyName = rel.AXF_CER_LKP_Counterparty__r.AXF_CPTY_TXT_DisplayName__c;
      dto.role = rel.AXF_CER_PKL_Role__c;
      dto.status = rel.AXF_CER_PKL_Status__c;
      dto.entitySpecificDisplay = rel.AXF_CER_TXT_EntitySpecificDisplay__c;
      result.add(dto);
    }
    return result;
  }

  /**
   * @description Cria um novo Contrato em estado DRAFT (AC 1).
   */
  public OperationResultDTO createDraftContract(ContractInputDTO input) {
    if (input == null) {
      throw new AXF_CLS_ContractException('Payload de entrada é obrigatório.');
    }
    if (input.accountId == null) {
      throw new AXF_CLS_ContractException('A Entidade titular (Account) é obrigatória.');
    }
    if (input.relationshipId == null) {
      throw new AXF_CLS_ContractException('A Relação contratual com contraparte é obrigatória.');
    }
    if (String.isBlank(input.contractCode)) {
      throw new AXF_CLS_ContractException('O Código do contrato é obrigatório.');
    }
    if (String.isBlank(input.title)) {
      throw new AXF_CLS_ContractException('O Título do contrato é obrigatório.');
    }
    if (String.isBlank(input.contractType) || (input.contractType != 'REVENUE' && input.contractType != 'EXPENSE')) {
      throw new AXF_CLS_ContractException('O Tipo do contrato é obrigatório e deve ser REVENUE ou EXPENSE.');
    }
    if (String.isNotBlank(input.lifecycle) && input.lifecycle != 'DRAFT') {
      throw new AXF_CLS_ContractException('Novos contratos devem ser criados no estado DRAFT.');
    }
    if (input.startDate != null && input.endDate != null && input.endDate < input.startDate) {
      throw new AXF_CLS_ContractException('A data de término não pode ser anterior à data de início.');
    }

    Account acc = validateAccountAccess(input.accountId);

    // Valida a relação contratual: compatibilidade com a entidade e status ativo (AC 1)
    List<AXF_OBJ_CounterpartyEntityRelationship__c> relationships = [
      SELECT
        Id,
        AXF_CER_LKP_Account__c,
        AXF_CER_LKP_Counterparty__c,
        AXF_CER_PKL_Status__c,
        AXF_CER_PKL_Role__c
      FROM AXF_OBJ_CounterpartyEntityRelationship__c
      WHERE Id = :input.relationshipId
      LIMIT 1
    ];

    if (relationships.isEmpty()) {
      throw new AXF_CLS_ContractException('Relação contratual não encontrada.');
    }

    AXF_OBJ_CounterpartyEntityRelationship__c rel = relationships[0];

    // Rejeição de combinação incompatível de titular e relação (cross-entity rejection)
    if (rel.AXF_CER_LKP_Account__c != input.accountId) {
      throw new AXF_CLS_ContractException('Combinação incompatível: a relação contratual pertence a outra Entidade.');
    }

    // Rejeição de relação inativa
    if (rel.AXF_CER_PKL_Status__c != 'ACTIVE') {
      throw new AXF_CLS_ContractException('A relação contratual selecionada não está ativa (status: ' + rel.AXF_CER_PKL_Status__c + ').');
    }

    // Valida contraparte informada, se enviada
    if (input.counterpartyId != null && input.counterpartyId != rel.AXF_CER_LKP_Counterparty__c) {
      throw new AXF_CLS_ContractException('A contraparte informada é incompatível com a relação contratual selecionada.');
    }

    // Idempotência por ClientRequestId (G6)
    if (String.isNotBlank(input.clientRequestId)) {
      List<AXF_OBJ_Contract__c> existingByRequestId = [
        SELECT
          Id,
          AXF_CTR_LKP_Account__c,
          AXF_CTR_LKP_Relationship__c,
          AXF_CTR_TXT_ContractCode__c,
          AXF_CTR_TXT_Title__c,
          AXF_CTR_PKL_Lifecycle__c,
          AXF_CTR_PKL_Type__c,
          AXF_CTR_NUM_Version__c
        FROM AXF_OBJ_Contract__c
        WHERE AXF_CTR_EXI_ClientRequestId__c = :input.clientRequestId
        LIMIT 1
      ];

      if (!existingByRequestId.isEmpty()) {
        AXF_OBJ_Contract__c existing = existingByRequestId[0];
        // Idempotent replay se os parâmetros coincidem
        if (existing.AXF_CTR_LKP_Account__c == input.accountId &&
            existing.AXF_CTR_LKP_Relationship__c == input.relationshipId &&
            existing.AXF_CTR_TXT_ContractCode__c.equalsIgnoreCase(input.contractCode.trim())) {
          OperationResultDTO replayResult = new OperationResultDTO();
          replayResult.success = true;
          replayResult.message = 'Contrato recuperado por requisição idempotente já processada.';
          replayResult.contractId = existing.Id;
          replayResult.version = existing.AXF_CTR_NUM_Version__c.longValue();
          return replayResult;
        } else {
          throw new AXF_CLS_ContractException('Conflito de idempotência: requisição com mesmo clientRequestId possui parâmetros divergentes.');
        }
      }
    }

    // Constrói chave canônica do contrato
    String contractKey = buildContractKey(input.accountId, input.contractCode);

    // Valida se já existe contrato com este código para esta Entidade
    List<AXF_OBJ_Contract__c> existingContracts = [
      SELECT Id
      FROM AXF_OBJ_Contract__c
      WHERE AXF_CTR_EXI_ContractKey__c = :contractKey
      LIMIT 1
    ];
    if (!existingContracts.isEmpty()) {
      throw new AXF_CLS_ContractException('Já existe um contrato cadastrado com este código para esta Entidade.');
    }

    // Cria o root canônico em DRAFT (AC 1)
    AXF_OBJ_Contract__c ctr = new AXF_OBJ_Contract__c();
    ctr.AXF_CTR_LKP_Account__c = input.accountId;
    ctr.AXF_CTR_LKP_Counterparty__c = rel.AXF_CER_LKP_Counterparty__c;
    ctr.AXF_CTR_LKP_Relationship__c = rel.Id;
    ctr.AXF_CTR_TXT_ContractCode__c = input.contractCode.trim();
    ctr.AXF_CTR_EXI_ContractKey__c = contractKey;
    ctr.AXF_CTR_TXT_Title__c = input.title.trim();
    ctr.AXF_CTR_PKL_Lifecycle__c = 'DRAFT';
    ctr.AXF_CTR_PKL_Type__c = input.contractType;
    ctr.AXF_CTR_TXT_CurrencyIsoCode__c = String.isNotBlank(input.currencyIsoCode) ? input.currencyIsoCode.trim().toUpperCase() : 'BRL';
    ctr.AXF_CTR_DAT_StartDate__c = input.startDate;
    ctr.AXF_CTR_DAT_EndDate__c = input.endDate;
    ctr.AXF_CTR_TAL_Description__c = input.description;
    ctr.AXF_CTR_NUM_Version__c = 1;
    ctr.AXF_CTR_EXI_ClientRequestId__c = input.clientRequestId;

    insert ctr;

    // Compartilhamento Apex Managed Sharing (RowCause AXF_ContractAccess__c)
    grantSharingPrivileged(ctr.Id, acc.OwnerId);

    OperationResultDTO result = new OperationResultDTO();
    result.success = true;
    result.message = 'Contrato em rascunho criado com sucesso.';
    result.contractId = ctr.Id;
    result.version = 1;
    return result;
  }

  /**
   * @description Edita dados não efetivos de um Contrato em DRAFT (AC 2).
   */
  public OperationResultDTO updateDraftContract(ContractInputDTO input) {
    if (input == null || input.contractId == null) {
      throw new AXF_CLS_ContractException('ID do Contrato é obrigatório para atualização.');
    }

    List<AXF_OBJ_Contract__c> contracts = [
      SELECT
        Id,
        AXF_CTR_LKP_Account__c,
        AXF_CTR_LKP_Counterparty__c,
        AXF_CTR_LKP_Relationship__c,
        AXF_CTR_TXT_ContractCode__c,
        AXF_CTR_EXI_ContractKey__c,
        AXF_CTR_TXT_Title__c,
        AXF_CTR_PKL_Lifecycle__c,
        AXF_CTR_PKL_Type__c,
        AXF_CTR_TXT_CurrencyIsoCode__c,
        AXF_CTR_DAT_StartDate__c,
        AXF_CTR_DAT_EndDate__c,
        AXF_CTR_TAL_Description__c,
        AXF_CTR_NUM_Version__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :input.contractId
      LIMIT 1
    ];

    if (contracts.isEmpty()) {
      throw new AXF_CLS_ContractException('Contrato não encontrado ou acesso negado.');
    }

    AXF_OBJ_Contract__c existing = contracts[0];

    // Invariante de DRAFT: apenas dados em DRAFT podem ser editados (AC 2)
    if (existing.AXF_CTR_PKL_Lifecycle__c != 'DRAFT') {
      throw new AXF_CLS_ContractException('Apenas contratos em rascunho (DRAFT) podem ter seus dados editados.');
    }

    // Bloqueio canônico de alteração de lifecycle nesta história (AC 3)
    if (String.isNotBlank(input.lifecycle) && input.lifecycle != 'DRAFT') {
      throw new AXF_CLS_ContractException('Transição de ciclo de vida bloqueada: operação canônica de término, cancelamento, ativação ou substituição ainda não disponível.');
    }

    // Invariante de imutabilidade de identidade (AC 3):
    // Entidade titular e Código do contrato NÃO podem ser alterados após criação
    if (input.accountId != null && input.accountId != existing.AXF_CTR_LKP_Account__c) {
      throw new AXF_CLS_ContractException('A Entidade titular de um contrato não pode ser alterada.');
    }
    if (String.isNotBlank(input.contractCode) && !input.contractCode.trim().equalsIgnoreCase(existing.AXF_CTR_TXT_ContractCode__c)) {
      throw new AXF_CLS_ContractException('O código canônico do contrato não pode ser alterado após a criação.');
    }

    // Concorrência Otimista (expectedVersion, G6)
    if (input.version != null && input.version != existing.AXF_CTR_NUM_Version__c) {
      throw new AXF_CLS_ContractException('Conflito de concorrência: o contrato foi alterado por outro usuário (versão informada: ' + input.version + ', atual: ' + existing.AXF_CTR_NUM_Version__c + ').');
    }

    // Se a relação for alterada, revalidar se pertence à mesma entidade e está ativa
    if (input.relationshipId != null && input.relationshipId != existing.AXF_CTR_LKP_Relationship__c) {
      List<AXF_OBJ_CounterpartyEntityRelationship__c> relationships = [
        SELECT
          Id,
          AXF_CER_LKP_Account__c,
          AXF_CER_LKP_Counterparty__c,
          AXF_CER_PKL_Status__c
        FROM AXF_OBJ_CounterpartyEntityRelationship__c
        WHERE Id = :input.relationshipId
        LIMIT 1
      ];
      if (relationships.isEmpty() || relationships[0].AXF_CER_LKP_Account__c != existing.AXF_CTR_LKP_Account__c) {
        throw new AXF_CLS_ContractException('Combinação incompatível: a nova relação informada não pertence à Entidade titular.');
      }
      if (relationships[0].AXF_CER_PKL_Status__c != 'ACTIVE') {
        throw new AXF_CLS_ContractException('A nova relação informada não está ativa.');
      }
      existing.AXF_CTR_LKP_Relationship__c = relationships[0].Id;
      existing.AXF_CTR_LKP_Counterparty__c = relationships[0].AXF_CER_LKP_Counterparty__c;
    }

    // Atualiza campos não efetivos
    if (String.isNotBlank(input.title)) {
      existing.AXF_CTR_TXT_Title__c = input.title.trim();
    }
    if (String.isNotBlank(input.contractType)) {
      if (input.contractType != 'REVENUE' && input.contractType != 'EXPENSE') {
        throw new AXF_CLS_ContractException('O Tipo do contrato deve ser REVENUE ou EXPENSE.');
      }
      existing.AXF_CTR_PKL_Type__c = input.contractType;
    }
    if (input.currencyIsoCode != null) {
      existing.AXF_CTR_TXT_CurrencyIsoCode__c = input.currencyIsoCode.trim().toUpperCase();
    }

    Date newStart = (input.startDate != null) ? input.startDate : existing.AXF_CTR_DAT_StartDate__c;
    Date newEnd = (input.endDate != null) ? input.endDate : existing.AXF_CTR_DAT_EndDate__c;
    if (newStart != null && newEnd != null && newEnd < newStart) {
      throw new AXF_CLS_ContractException('A data de término não pode ser anterior à data de início.');
    }

    existing.AXF_CTR_DAT_StartDate__c = input.startDate;
    existing.AXF_CTR_DAT_EndDate__c = input.endDate;
    existing.AXF_CTR_TAL_Description__c = input.description;

    // Incrementa versão (expectedVersion, G6)
    existing.AXF_CTR_NUM_Version__c = existing.AXF_CTR_NUM_Version__c + 1;

    update existing;

    OperationResultDTO result = new OperationResultDTO();
    result.success = true;
    result.message = 'Rascunho do contrato atualizado com sucesso.';
    result.contractId = existing.Id;
    result.version = existing.AXF_CTR_NUM_Version__c.longValue();
    return result;
  }

  /**
   * @description Tentativa explícita de transição de ciclo de vida (cancelamento, término, substituição).
   * Bloqueada canonicamente conforme AC 3.
   */
  public void attemptLifecycleTransition(Id contractId, String targetLifecycle) {
    if (contractId == null) {
      throw new AXF_CLS_ContractException('ID do contrato é obrigatório.');
    }
    // Bloqueio rigoroso do critério de aceite 3
    throw new AXF_CLS_ContractException('Transição de ciclo de vida bloqueada: operação canônica de término, cancelamento, ativação ou substituição ainda não disponível.');
  }

  /**
   * @description Valida acesso à Entidade e retorna o registro.
   */
  private static Account validateAccountAccess(Id accountId) {
    List<Account> accounts = [
      SELECT Id, Name, OwnerId
      FROM Account
      WHERE Id = :accountId
      LIMIT 1
    ];
    if (accounts.isEmpty()) {
      throw new AXF_CLS_ContractException('Acesso negado ou Entidade não encontrada.');
    }
    return accounts[0];
  }

  /**
   * @description Concede compartilhamento gerenciado por Apex para o proprietário da Entidade (G2).
   */
  private static void grantSharingPrivileged(Id contractId, Id entityOwnerId) {
    if (entityOwnerId == null || contractId == null) {
      return;
    }

    try {
      AXF_OBJ_Contract__Share ctrShare = new AXF_OBJ_Contract__Share();
      ctrShare.ParentId = contractId;
      ctrShare.UserOrGroupId = entityOwnerId;
      ctrShare.AccessLevel = 'Edit';
      ctrShare.RowCause = Schema.AXF_OBJ_Contract__Share.RowCause.AXF_ContractAccess__c;
      Database.insert(ctrShare, false);
    } catch (Exception e) {
      // Ignora se o usuário já possuir acesso direto ou superior
    }
  }
}
