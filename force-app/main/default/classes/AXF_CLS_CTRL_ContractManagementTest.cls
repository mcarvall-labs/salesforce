/**
 * @description Testes unitários para AXF_CLS_CTRL_ContractManagement (AXF-52).
 * Cobre:
 * - Consulta de entidades autorizadas (getAuthorizedEntities).
 * - Consulta de relações ativas (getActiveRelationships).
 * - Listagem de contratos por entidade (getContracts).
 * - Detalhamento de contrato (getContractDetail).
 * - Criação e atualização de contrato em rascunho (createDraftContract, updateDraftContract).
 * - Normalização de exceções em AuraHandledException.
 */
@IsTest
private class AXF_CLS_CTRL_ContractManagementTest {

  private static Account createTestAccount(String name) {
    Account acc = new Account(Name = name);
    Id bRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('AXF_Business')?.getRecordTypeId();
    if (bRtId != null) {
      acc.RecordTypeId = bRtId;
    }
    insert acc;
    return acc;
  }

  private static AXF_OBJ_Counterparty__c createTestCounterparty(String name) {
    AXF_OBJ_Counterparty__c cpty = new AXF_OBJ_Counterparty__c(
      Name = name,
      AXF_CPTY_TXT_DisplayName__c = name,
      AXF_CPTY_TXT_LegalName__c = name + ' LTDA',
      AXF_CPTY_TXT_Country__c = 'BR',
      AXF_CPTY_PKL_Kind__c = 'ORGANIZATION',
      AXF_CPTY_PKL_Status__c = 'ACTIVE',
      AXF_CPTY_EXI_CounterpartyKey__c = AXF_CLS_IdentityFraming.key(new List<Object>{ 'CPTY', name + ' LTDA', 'BR' }),
      AXF_CPTY_NUM_Version__c = 1
    );
    insert cpty;
    return cpty;
  }

  private static AXF_OBJ_CounterpartyEntityRelationship__c createTestRelationship(Id cptyId, Id accId, String status) {
    AXF_OBJ_CounterpartyEntityRelationship__c rel = new AXF_OBJ_CounterpartyEntityRelationship__c(
      AXF_CER_LKP_Counterparty__c = cptyId,
      AXF_CER_LKP_Account__c = accId,
      AXF_CER_PKL_Role__c = 'SUPPLIER',
      AXF_CER_PKL_Status__c = status,
      AXF_CER_TXT_EntitySpecificDisplay__c = 'Fornecedor Teste',
      AXF_CER_EXI_RelationshipKey__c = AXF_CLS_IdentityFraming.key(new List<Object>{ 'CER', cptyId, accId, 'SUPPLIER' }),
      AXF_CER_NUM_Version__c = 1
    );
    insert rel;
    return rel;
  }

  @IsTest
  static void testGetAuthorizedEntities() {
    Test.startTest();
    List<AXF_CLS_AuthorizedContextService.ContextView> contexts = AXF_CLS_CTRL_ContractManagement.getAuthorizedEntities();
    Test.stopTest();

    Assert.isNotNull(contexts, 'Contextos autorizados retornados');
  }

  @IsTest
  static void testGetActiveRelationships() {
    Account acc = createTestAccount('Entidade Controller Rels');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Controller');
    createTestRelationship(cpty.Id, acc.Id, 'ACTIVE');

    Test.startTest();
    List<ALT_CLS_ContractService.ActiveRelationshipDTO> rels = AXF_CLS_CTRL_ContractManagement.getActiveRelationships(acc.Id);
    Test.stopTest();

    Assert.areEqual(1, rels.size(), 'Deve retornar 1 relação ativa');

    try {
      AXF_CLS_CTRL_ContractManagement.getActiveRelationships(null);
      Assert.fail('Deveria falhar sem accountId');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e);
    }
  }

  @IsTest
  static void testContractsCrudViaController() {
    Account acc = createTestAccount('Entidade Contratos Controller');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Teste Ctr');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id, 'ACTIVE');

    ALT_CLS_ContractService.ContractInputDTO input = new ALT_CLS_ContractService.ContractInputDTO();
    input.accountId = acc.Id;
    input.relationshipId = rel.Id;
    input.contractCode = 'CTR-CTRL-01';
    input.title = 'Contrato via Controller';
    input.contractType = 'REVENUE';
    input.currencyIsoCode = 'BRL';

    Test.startTest();
    ALT_CLS_ContractService.OperationResultDTO createRes = AXF_CLS_CTRL_ContractManagement.createDraftContract(input);
    Assert.isTrue(createRes.success, 'Criação com sucesso');

    List<ALT_CLS_ContractService.ContractSummaryDTO> contracts = AXF_CLS_CTRL_ContractManagement.getContracts(acc.Id);
    Assert.areEqual(1, contracts.size(), 'Deve retornar o contrato criado');

    ALT_CLS_ContractService.ContractDetailDTO detail = AXF_CLS_CTRL_ContractManagement.getContractDetail(createRes.contractId, acc.Id);
    Assert.areEqual('Contrato via Controller', detail.title, 'Título coincide');

    ALT_CLS_ContractService.ContractInputDTO updateInput = new ALT_CLS_ContractService.ContractInputDTO();
    updateInput.contractId = createRes.contractId;
    updateInput.title = 'Contrato via Controller - Atualizado';
    updateInput.version = 1;

    ALT_CLS_ContractService.OperationResultDTO updateRes = AXF_CLS_CTRL_ContractManagement.updateDraftContract(updateInput);
    Assert.isTrue(updateRes.success, 'Atualização com sucesso');
    Assert.areEqual(2, updateRes.version, 'Versão incrementada');
    Test.stopTest();
  }

  @IsTest
  static void testControllerErrorHandling() {
    try {
      AXF_CLS_CTRL_ContractManagement.getContracts(null);
      Assert.fail('Deveria falhar com accountId nulo');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e);
    }

    try {
      AXF_CLS_CTRL_ContractManagement.getContractDetail(null, null);
      Assert.fail('Deveria falhar');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e);
    }

    try {
      AXF_CLS_CTRL_ContractManagement.createDraftContract(null);
      Assert.fail('Deveria falhar');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e);
    }

    try {
      AXF_CLS_CTRL_ContractManagement.updateDraftContract(null);
      Assert.fail('Deveria falhar');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e);
    }
  }
}
