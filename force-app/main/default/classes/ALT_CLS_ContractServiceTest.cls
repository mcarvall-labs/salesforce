/**
 * @description Testes unitários para ALT_CLS_ContractService (AXF-52).
 * Cobre:
 * - Criação de Contrato em rascunho (DRAFT) com vínculo exato a Entidade e Relação (AC 1).
 * - Rejeição de combinações incompatíveis de titular e relação (cross-entity isolation) (AC 1).
 * - Rejeição de relações inativas (AC 1).
 * - Chave canônica determinística e unicidade de código do contrato (G6).
 * - Edição de dados não efetivos em DRAFT com expectedVersion (concorrência otimista) (AC 2).
 * - Idempotência por ClientRequestId (replay e detecção de conflito) (G6).
 * - Garantia de que nenhum CashFlow ou documento financeiro é gerado implicitamente (AC 2).
 * - Bloqueio de operações de término, cancelamento ou substituição (AC 3).
 * - Imutabilidade da identidade canônica (Entidade e Código não alteráveis pós-criação) (AC 3).
 * - Isolamento de consultas entre entidades (GF-32).
 */
@IsTest
private class ALT_CLS_ContractServiceTest {

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
      AXF_CER_TXT_EntitySpecificDisplay__c = 'Fornecedor Principal',
      AXF_CER_EXI_RelationshipKey__c = AXF_CLS_IdentityFraming.key(new List<Object>{ 'CER', cptyId, accId, 'SUPPLIER' }),
      AXF_CER_NUM_Version__c = 1
    );
    insert rel;
    return rel;
  }

  @IsTest
  static void testCreateDraftContract_Success() {
    Account acc = createTestAccount('Empresa Alfa');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Fornecedor Beta');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id, 'ACTIVE');

    ALT_CLS_ContractService service = new ALT_CLS_ContractService();

    ALT_CLS_ContractService.ContractInputDTO input = new ALT_CLS_ContractService.ContractInputDTO();
    input.accountId = acc.Id;
    input.relationshipId = rel.Id;
    input.contractCode = 'CTR-2026-001';
    input.title = 'Prestação de Serviços de TI';
    input.contractType = 'EXPENSE';
    input.currencyIsoCode = 'BRL';
    input.startDate = Date.today();
    input.endDate = Date.today().addYears(1);
    input.description = 'Contrato anual de suporte técnico';

    Integer txCountBefore = [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c];

    Test.startTest();
    ALT_CLS_ContractService.OperationResultDTO res = service.createDraftContract(input);
    Test.stopTest();

    Assert.isTrue(res.success, 'Sucesso na criação do contrato em rascunho');
    Assert.isNotNull(res.contractId, 'ID do contrato retornado');
    Assert.areEqual(1, res.version, 'Versão inicial deve ser 1');

    // Validações do registro persistido
    AXF_OBJ_Contract__c ctr = [
      SELECT
        Id,
        Name,
        AXF_CTR_LKP_Account__c,
        AXF_CTR_LKP_Counterparty__c,
        AXF_CTR_LKP_Relationship__c,
        AXF_CTR_TXT_ContractCode__c,
        AXF_CTR_EXI_ContractKey__c,
        AXF_CTR_TXT_Title__c,
        AXF_CTR_PKL_Lifecycle__c,
        AXF_CTR_PKL_Type__c,
        AXF_CTR_TXT_CurrencyIsoCode__c,
        AXF_CTR_NUM_Version__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :res.contractId
    ];

    Assert.areEqual(acc.Id, ctr.AXF_CTR_LKP_Account__c, 'Entidade titular vinculada');
    Assert.areEqual(cpty.Id, ctr.AXF_CTR_LKP_Counterparty__c, 'Contraparte vinculada');
    Assert.areEqual(rel.Id, ctr.AXF_CTR_LKP_Relationship__c, 'Relação contratual vinculada');
    Assert.areEqual('CTR-2026-001', ctr.AXF_CTR_TXT_ContractCode__c, 'Código preservado');
    Assert.areEqual('DRAFT', ctr.AXF_CTR_PKL_Lifecycle__c, 'Lifecycle inicial canônico DRAFT');
    Assert.areEqual('EXPENSE', ctr.AXF_CTR_PKL_Type__c, 'Tipo de contrato');
    Assert.areEqual(1, ctr.AXF_CTR_NUM_Version__c, 'Versão numérica');

    // Invariante financeira: NENHUM CashFlow / FinancialTransaction gerado implicitamente (AC 2)
    Integer txCountAfter = [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c];
    Assert.areEqual(txCountBefore, txCountAfter, 'Nenhum lançamento financeiro deve ser gerado na criação do rascunho');
  }

  @IsTest
  static void testCreateDraftContract_IncompatibleEntity_Fails() {
    Account accA = createTestAccount('Empresa Titular A');
    Account accB = createTestAccount('Empresa Titular B');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Prestador');
    // Relação criada para Empresa B
    AXF_OBJ_CounterpartyEntityRelationship__c relB = createTestRelationship(cpty.Id, accB.Id, 'ACTIVE');

    ALT_CLS_ContractService service = new ALT_CLS_ContractService();

    ALT_CLS_ContractService.ContractInputDTO input = new ALT_CLS_ContractService.ContractInputDTO();
    input.accountId = accA.Id; // Tentativa com Empresa A mas relação da Empresa B
    input.relationshipId = relB.Id;
    input.contractCode = 'CTR-CROSS-01';
    input.title = 'Contrato Incompatível';
    input.contractType = 'REVENUE';

    try {
      service.createDraftContract(input);
      Assert.fail('Deveria ter lançado exceção de relação incompatível');
    } catch (AXF_CLS_ContractException e) {
      Assert.isTrue(e.getMessage().contains('incompatível'), 'Exceção de incompatibilidade esperada');
    }
  }

  @IsTest
  static void testCreateDraftContract_InactiveRelationship_Fails() {
    Account acc = createTestAccount('Empresa Ativa');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Fornecedor Inativo');
    AXF_OBJ_CounterpartyEntityRelationship__c relInactive = createTestRelationship(cpty.Id, acc.Id, 'INACTIVE');

    ALT_CLS_ContractService service = new ALT_CLS_ContractService();

    ALT_CLS_ContractService.ContractInputDTO input = new ALT_CLS_ContractService.ContractInputDTO();
    input.accountId = acc.Id;
    input.relationshipId = relInactive.Id;
    input.contractCode = 'CTR-INACT-01';
    input.title = 'Contrato com Relação Inativa';
    input.contractType = 'EXPENSE';

    try {
      service.createDraftContract(input);
      Assert.fail('Deveria falhar com relação inativa');
    } catch (AXF_CLS_ContractException e) {
      Assert.isTrue(e.getMessage().contains('não está ativa'), 'Exceção de status inativo esperada');
    }
  }

  @IsTest
  static void testCreateDraftContract_DuplicateContractCode_Fails() {
    Account acc = createTestAccount('Empresa Repetida');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Fornecedor Gama');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id, 'ACTIVE');

    ALT_CLS_ContractService service = new ALT_CLS_ContractService();

    ALT_CLS_ContractService.ContractInputDTO input1 = new ALT_CLS_ContractService.ContractInputDTO();
    input1.accountId = acc.Id;
    input1.relationshipId = rel.Id;
    input1.contractCode = 'CTR-DUP-01';
    input1.title = 'Contrato Original';
    input1.contractType = 'REVENUE';
    service.createDraftContract(input1);

    ALT_CLS_ContractService.ContractInputDTO input2 = new ALT_CLS_ContractService.ContractInputDTO();
    input2.accountId = acc.Id;
    input2.relationshipId = rel.Id;
    input2.contractCode = 'CTR-DUP-01'; // Código duplicado para a mesma entidade
    input2.title = 'Contrato Duplicado';
    input2.contractType = 'REVENUE';

    try {
      service.createDraftContract(input2);
      Assert.fail('Deveria falhar por duplicidade de código na mesma entidade');
    } catch (AXF_CLS_ContractException e) {
      Assert.isTrue(e.getMessage().contains('Já existe um contrato'), 'Exceção de duplicidade esperada');
    }
  }

  @IsTest
  static void testCreateDraftContract_NonDraftLifecycle_Fails() {
    Account acc = createTestAccount('Empresa Teste Lifecycle');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Parceiro');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id, 'ACTIVE');

    ALT_CLS_ContractService service = new ALT_CLS_ContractService();

    ALT_CLS_ContractService.ContractInputDTO input = new ALT_CLS_ContractService.ContractInputDTO();
    input.accountId = acc.Id;
    input.relationshipId = rel.Id;
    input.contractCode = 'CTR-ACT-01';
    input.title = 'Tentativa de Criar Ativo Direto';
    input.contractType = 'REVENUE';
    input.lifecycle = 'ACTIVE';

    try {
      service.createDraftContract(input);
      Assert.fail('Deveria falhar ao tentar criar contrato com lifecycle diferente de DRAFT');
    } catch (AXF_CLS_ContractException e) {
      Assert.isTrue(e.getMessage().contains('DRAFT'), 'Exceção de lifecycle inicial obrigatório DRAFT');
    }
  }

  @IsTest
  static void testCreateDraftContract_Idempotency() {
    Account acc = createTestAccount('Empresa Idempotente');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Fornecedor Idem');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id, 'ACTIVE');

    ALT_CLS_ContractService service = new ALT_CLS_ContractService();

    String clientReqId = 'IDEM-REQ-' + System.currentTimeMillis();

    ALT_CLS_ContractService.ContractInputDTO input = new ALT_CLS_ContractService.ContractInputDTO();
    input.accountId = acc.Id;
    input.relationshipId = rel.Id;
    input.contractCode = 'CTR-IDEM-01';
    input.title = 'Contrato Idempotente';
    input.contractType = 'EXPENSE';
    input.clientRequestId = clientReqId;

    // Primeira chamada
    ALT_CLS_ContractService.OperationResultDTO res1 = service.createDraftContract(input);
    Assert.isTrue(res1.success, 'Primeira chamada com sucesso');

    // Replay idempotente idêntico
    ALT_CLS_ContractService.OperationResultDTO res2 = service.createDraftContract(input);
    Assert.isTrue(res2.success, 'Segunda chamada idêntica com sucesso');
    Assert.areEqual(res1.contractId, res2.contractId, 'Mesmo contrato retornado no replay');

    // Tentativa de conflito: mesmo clientRequestId com parâmetros divergentes
    ALT_CLS_ContractService.ContractInputDTO inputConflict = new ALT_CLS_ContractService.ContractInputDTO();
    inputConflict.accountId = acc.Id;
    inputConflict.relationshipId = rel.Id;
    inputConflict.contractCode = 'CTR-IDEM-DIVERGENTE';
    inputConflict.title = 'Contrato Divergente';
    inputConflict.contractType = 'EXPENSE';
    inputConflict.clientRequestId = clientReqId;

    try {
      service.createDraftContract(inputConflict);
      Assert.fail('Deveria lançar conflito de idempotência com payload divergente');
    } catch (AXF_CLS_ContractException e) {
      Assert.isTrue(e.getMessage().contains('Conflito de idempotência'), 'Exceção de conflito esperada');
    }
  }

  @IsTest
  static void testUpdateDraftContract_SuccessAndOptimisticLock() {
    Account acc = createTestAccount('Empresa Update');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Fornecedor Delta');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id, 'ACTIVE');

    ALT_CLS_ContractService service = new ALT_CLS_ContractService();

    ALT_CLS_ContractService.ContractInputDTO input = new ALT_CLS_ContractService.ContractInputDTO();
    input.accountId = acc.Id;
    input.relationshipId = rel.Id;
    input.contractCode = 'CTR-UPD-01';
    input.title = 'Título Rascunho 1';
    input.contractType = 'REVENUE';
    ALT_CLS_ContractService.OperationResultDTO createRes = service.createDraftContract(input);

    // Edição válida de campos não efetivos
    ALT_CLS_ContractService.ContractInputDTO updateInput = new ALT_CLS_ContractService.ContractInputDTO();
    updateInput.contractId = createRes.contractId;
    updateInput.title = 'Título Atualizado v2';
    updateInput.description = 'Nova descrição do rascunho';
    updateInput.contractType = 'REVENUE';
    updateInput.currencyIsoCode = 'USD';
    updateInput.startDate = Date.today();
    updateInput.endDate = Date.today().addMonths(6);
    updateInput.version = 1; // expectedVersion coincide

    ALT_CLS_ContractService.OperationResultDTO updateRes = service.updateDraftContract(updateInput);
    Assert.isTrue(updateRes.success, 'Atualização com sucesso');
    Assert.areEqual(2, updateRes.version, 'Versão incrementada para 2');

    // Concorrência Otimista: envio com versão defasada (esperava 2, enviou 1)
    ALT_CLS_ContractService.ContractInputDTO staleInput = new ALT_CLS_ContractService.ContractInputDTO();
    staleInput.contractId = createRes.contractId;
    staleInput.title = 'Tentativa Concorrente';
    staleInput.version = 1;

    try {
      service.updateDraftContract(staleInput);
      Assert.fail('Deveria falhar por conflito de versão');
    } catch (AXF_CLS_ContractException e) {
      Assert.isTrue(e.getMessage().contains('Conflito de concorrência'), 'Exceção de concorrência esperada');
    }
  }

  @IsTest
  static void testUpdateDraftContract_IdentityImmutability() {
    Account acc1 = createTestAccount('Empresa Imutável 1');
    Account acc2 = createTestAccount('Empresa Imutável 2');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Fornecedor Fixo');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc1.Id, 'ACTIVE');

    ALT_CLS_ContractService service = new ALT_CLS_ContractService();

    ALT_CLS_ContractService.ContractInputDTO input = new ALT_CLS_ContractService.ContractInputDTO();
    input.accountId = acc1.Id;
    input.relationshipId = rel.Id;
    input.contractCode = 'CTR-IMM-01';
    input.title = 'Contrato Base';
    input.contractType = 'EXPENSE';
    ALT_CLS_ContractService.OperationResultDTO createRes = service.createDraftContract(input);

    // Tentativa de alterar a Entidade titular
    ALT_CLS_ContractService.ContractInputDTO changeAccInput = new ALT_CLS_ContractService.ContractInputDTO();
    changeAccInput.contractId = createRes.contractId;
    changeAccInput.accountId = acc2.Id;

    try {
      service.updateDraftContract(changeAccInput);
      Assert.fail('Deveria falhar ao tentar alterar a Entidade');
    } catch (AXF_CLS_ContractException e) {
      Assert.isTrue(e.getMessage().contains('não pode ser alterada'), 'Exceção esperada para titular');
    }

    // Tentativa de alterar o código do contrato
    ALT_CLS_ContractService.ContractInputDTO changeCodeInput = new ALT_CLS_ContractService.ContractInputDTO();
    changeCodeInput.contractId = createRes.contractId;
    changeCodeInput.contractCode = 'CTR-IMM-ALTERADO';

    try {
      service.updateDraftContract(changeCodeInput);
      Assert.fail('Deveria falhar ao tentar alterar o código');
    } catch (AXF_CLS_ContractException e) {
      Assert.isTrue(e.getMessage().contains('não pode ser alterado'), 'Exceção esperada para código');
    }
  }

  @IsTest
  static void testAttemptLifecycleTransition_Blocked() {
    Account acc = createTestAccount('Empresa Transição');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Fornecedor Bloqueado');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id, 'ACTIVE');

    ALT_CLS_ContractService service = new ALT_CLS_ContractService();

    ALT_CLS_ContractService.ContractInputDTO input = new ALT_CLS_ContractService.ContractInputDTO();
    input.accountId = acc.Id;
    input.relationshipId = rel.Id;
    input.contractCode = 'CTR-BLOCKED-01';
    input.title = 'Contrato em Rascunho';
    input.contractType = 'EXPENSE';
    ALT_CLS_ContractService.OperationResultDTO createRes = service.createDraftContract(input);

    // Teste de chamada direta do método de ciclo de vida (AC 3)
    try {
      service.attemptLifecycleTransition(createRes.contractId, 'CANCELLED');
      Assert.fail('Deveria bloquear transição de ciclo de vida');
    } catch (AXF_CLS_ContractException e) {
      Assert.isTrue(e.getMessage().contains('bloqueada'), 'Transição bloqueada esperada');
    }

    // Teste de tentativa via updateDraftContract passando lifecycle diferente de DRAFT (AC 3)
    ALT_CLS_ContractService.ContractInputDTO updateInput = new ALT_CLS_ContractService.ContractInputDTO();
    updateInput.contractId = createRes.contractId;
    updateInput.lifecycle = 'CANCELLED';

    try {
      service.updateDraftContract(updateInput);
      Assert.fail('Deveria bloquear alteração de lifecycle via update');
    } catch (AXF_CLS_ContractException e) {
      Assert.isTrue(e.getMessage().contains('bloqueada'), 'Transição via update bloqueada esperada');
    }
  }

  @IsTest
  static void testGetContractsAndDetail_AndCrossEntityIsolation() {
    Account accA = createTestAccount('Empresa Isolada A');
    Account accB = createTestAccount('Empresa Isolada B');
    AXF_OBJ_Counterparty__c cptyA = createTestCounterparty('Fornecedor de A');
    AXF_OBJ_CounterpartyEntityRelationship__c relA = createTestRelationship(cptyA.Id, accA.Id, 'ACTIVE');

    ALT_CLS_ContractService service = new ALT_CLS_ContractService();

    ALT_CLS_ContractService.ContractInputDTO input = new ALT_CLS_ContractService.ContractInputDTO();
    input.accountId = accA.Id;
    input.relationshipId = relA.Id;
    input.contractCode = 'CTR-ISO-01';
    input.title = 'Contrato Exclusivo de A';
    input.contractType = 'REVENUE';
    ALT_CLS_ContractService.OperationResultDTO createRes = service.createDraftContract(input);

    // Consulta para Empresa A: deve retornar o contrato
    List<ALT_CLS_ContractService.ContractSummaryDTO> listA = service.getContractsByAccount(accA.Id);
    Assert.areEqual(1, listA.size(), 'Deve listar 1 contrato para Empresa A');
    Assert.areEqual('CTR-ISO-01', listA[0].contractCode, 'Código coincide');

    // Detalhe para Empresa A
    ALT_CLS_ContractService.ContractDetailDTO detail = service.getContractDetail(createRes.contractId, accA.Id);
    Assert.areEqual('Contrato Exclusivo de A', detail.title, 'Título detalhado');
    Assert.isNotNull(detail.contractKey, 'Chave canônica preenchida');

    // Consulta para Empresa B: isolamento total, NÃO deve retornar contrato de A
    List<ALT_CLS_ContractService.ContractSummaryDTO> listB = service.getContractsByAccount(accB.Id);
    Assert.areEqual(0, listB.size(), 'Empresa B não deve enxergar contratos de Empresa A');

    // Tentativa de obter detalhe de contrato de A usando contexto de Empresa B: falha
    try {
      service.getContractDetail(createRes.contractId, accB.Id);
      Assert.fail('Deveria falhar ao buscar contrato de outra entidade');
    } catch (AXF_CLS_ContractException e) {
      Assert.isTrue(e.getMessage().contains('não pertence'), 'Exceção de isolamento esperada');
    }

    // Active relationships
    List<ALT_CLS_ContractService.ActiveRelationshipDTO> activeRels = service.getActiveRelationships(accA.Id);
    Assert.areEqual(1, activeRels.size(), 'Deve listar 1 relação ativa para A');
    Assert.areEqual(relA.Id, activeRels[0].relationshipId, 'ID da relação coincide');
  }

  @IsTest
  static void testValidationErrors() {
    ALT_CLS_ContractService service = new ALT_CLS_ContractService();

    try {
      service.createDraftContract(null);
      Assert.fail('Deveria falhar com payload nulo');
    } catch (AXF_CLS_ContractException e) {
      Assert.isTrue(e.getMessage().contains('obrigatório'), 'Exceção esperada');
    }

    try {
      service.getContractsByAccount(null);
      Assert.fail('Deveria falhar sem accountId');
    } catch (AXF_CLS_ContractException e) {
      Assert.isTrue(e.getMessage().contains('obrigatório'), 'Exceção esperada');
    }

    try {
      service.getActiveRelationships(null);
      Assert.fail('Deveria falhar sem accountId');
    } catch (AXF_CLS_ContractException e) {
      Assert.isTrue(e.getMessage().contains('obrigatório'), 'Exceção esperada');
    }

    try {
      service.updateDraftContract(null);
      Assert.fail('Deveria falhar sem payload');
    } catch (AXF_CLS_ContractException e) {
      Assert.isTrue(e.getMessage().contains('obrigatório'), 'Exceção esperada');
    }

    try {
      service.attemptLifecycleTransition(null, 'ACTIVE');
      Assert.fail('Deveria falhar sem contractId');
    } catch (AXF_CLS_ContractException e) {
      Assert.isTrue(e.getMessage().contains('obrigatório'), 'Exceção esperada');
    }

    try {
      ALT_CLS_ContractService.buildContractKey(null, 'CTR-1');
      Assert.fail('Deveria falhar sem accountId');
    } catch (AXF_CLS_ContractException e) {
      Assert.isTrue(e.getMessage().contains('obrigatórios'), 'Exceção esperada');
    }
  }
}
