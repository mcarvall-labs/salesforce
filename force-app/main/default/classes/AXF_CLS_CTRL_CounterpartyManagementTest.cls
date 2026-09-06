/**
 * @description Testes unitários para AXF_CLS_CTRL_CounterpartyManagement (AXF-51).
 * Cobre:
 * - Consulta de entidades autorizadas (getAuthorizedEntities).
 * - Listagem de contrapartes por entidade e tratamento de erros (getCounterparties).
 * - Detalhamento da contraparte e isolamento por entidade (getCounterpartyDetail).
 * - Criação/atualização de contraparte (saveCounterparty).
 * - Normalização de exceções de negócio em AuraHandledException.
 */
@IsTest
private class AXF_CLS_CTRL_CounterpartyManagementTest {

  private static Account createTestAccount(String name) {
    Account acc = new Account(Name = name);
    Id bRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('AXF_Business')?.getRecordTypeId();
    if (bRtId != null) {
      acc.RecordTypeId = bRtId;
    }
    insert acc;
    return acc;
  }

  @IsTest
  static void testGetAuthorizedEntities() {
    Test.startTest();
    List<AXF_CLS_AuthorizedContextService.ContextView> contexts = AXF_CLS_CTRL_CounterpartyManagement.getAuthorizedEntities();
    Test.stopTest();

    Assert.isNotNull(contexts, 'Lista de entidades autorizadas não deve ser nula');
  }

  @IsTest
  static void testGetCounterpartiesSuccessAndError() {
    Account acc = createTestAccount('Entidade Controller Test');

    ALT_CLS_CounterpartyService.CounterpartyInputDTO input = new ALT_CLS_CounterpartyService.CounterpartyInputDTO();
    input.accountId = acc.Id;
    input.legalName = 'Empresa Fornecedora Beta S/A';
    input.displayName = 'Fornecedora Beta';
    input.country = 'BR';
    input.role = 'SUPPLIER';

    AXF_CLS_CTRL_CounterpartyManagement.saveCounterparty(input);

    Test.startTest();
    List<ALT_CLS_CounterpartyService.CounterpartySummaryDTO> listResult = AXF_CLS_CTRL_CounterpartyManagement.getCounterparties(acc.Id, 'Beta');
    Test.stopTest();

    Assert.areEqual(1, listResult.size());
    Assert.areEqual('Fornecedora Beta', listResult[0].displayName);

    // Erro: accountId nulo
    try {
      AXF_CLS_CTRL_CounterpartyManagement.getCounterparties(null, null);
      Assert.fail('Deveria lançar AuraHandledException para accountId nulo');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e, 'AuraHandledException lançada com sucesso');
    }
  }

  @IsTest
  static void testGetCounterpartyDetailSuccessAndError() {
    Account acc = createTestAccount('Entidade Detalhe Controller');

    ALT_CLS_CounterpartyService.CounterpartyInputDTO input = new ALT_CLS_CounterpartyService.CounterpartyInputDTO();
    input.accountId = acc.Id;
    input.legalName = 'Gamma Soluções Digitais LTDA';
    input.displayName = 'Gamma Soluções';
    input.country = 'BR';
    input.role = 'CLIENT';
    input.entitySpecificDisplay = 'Gamma - Matriz SP';

    ALT_CLS_CounterpartyService.OperationResultDTO saveRes = AXF_CLS_CTRL_CounterpartyManagement.saveCounterparty(input);

    Test.startTest();
    ALT_CLS_CounterpartyService.CounterpartyDetailDTO detail = AXF_CLS_CTRL_CounterpartyManagement.getCounterpartyDetail(saveRes.counterpartyId, acc.Id);
    Test.stopTest();

    Assert.isNotNull(detail);
    Assert.areEqual('Gamma Soluções', detail.displayName);
    Assert.areEqual('CLIENT', detail.role);
    Assert.areEqual('Gamma - Matriz SP', detail.entitySpecificDisplay);

    // Erro: counterpartyId nulo
    try {
      AXF_CLS_CTRL_CounterpartyManagement.getCounterpartyDetail(null, acc.Id);
      Assert.fail('Deveria lançar AuraHandledException');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e);
    }

    // Erro: accountId nulo
    try {
      AXF_CLS_CTRL_CounterpartyManagement.getCounterpartyDetail(saveRes.counterpartyId, null);
      Assert.fail('Deveria lançar AuraHandledException');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e);
    }
  }

  @IsTest
  static void testSaveCounterpartyPayloadValidation() {
    // Erro: payload nulo
    try {
      AXF_CLS_CTRL_CounterpartyManagement.saveCounterparty(null);
      Assert.fail('Deveria lançar AuraHandledException para payload nulo');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e);
    }

    // Erro de domínio capturado e convertido em AuraHandledException
    ALT_CLS_CounterpartyService.CounterpartyInputDTO invalidDTO = new ALT_CLS_CounterpartyService.CounterpartyInputDTO();
    invalidDTO.legalName = 'Sem Account';
    try {
      AXF_CLS_CTRL_CounterpartyManagement.saveCounterparty(invalidDTO);
      Assert.fail('Deveria converter AXF_CLS_CounterpartyException em AuraHandledException');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e);
    }
  }

  @IsTest
  static void testCounterpartyExceptionAndCatchBlocks() {
    AXF_CLS_CounterpartyException ex = new AXF_CLS_CounterpartyException('Mensagem de erro de teste');
    Assert.areEqual('Mensagem de erro de teste', ex.getMessage());

    Id fakeAccId = '001000000000001AAA';
    Id fakeCptyId = 'a01000000000001AAA';
    try {
      AXF_CLS_CTRL_CounterpartyManagement.getCounterpartyDetail(fakeCptyId, fakeAccId);
      Assert.fail('Deveria lançar AuraHandledException');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e);
    }

    try {
      AXF_CLS_CTRL_CounterpartyManagement.getCounterparties(fakeAccId, null);
      Assert.fail('Deveria lançar AuraHandledException');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e);
    }
  }
}
