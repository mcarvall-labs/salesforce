/**
 * @description Testes unitarios para ALT_CLS_WorkRecordService e AXF_TRG_WorkRecord (AXF-56).
 * Cobre:
 * 1. Registro e Reimportacao com EvidenceHash (AC 1).
 * 2. Ciclo de Vida DRAFT -> SUBMITTED -> APPROVED | REJECTED com auditoria (AC 2).
 * 3. Correcao de Registro Aprovado por reversao e substituicao (AC 3).
 * 4. Imutabilidade em banco de dados via Trigger (bloqueio de edicao e delete).
 * 5. Apuracao e gating de agenda para registros obrigatorios (AC 4).
 */
@IsTest
private class ALT_CLS_WorkRecordServiceTest {

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

  private static AXF_OBJ_CounterpartyEntityRelationship__c createTestRelationship(Id cptyId, Id accId) {
    AXF_OBJ_CounterpartyEntityRelationship__c rel = new AXF_OBJ_CounterpartyEntityRelationship__c(
      AXF_CER_LKP_Counterparty__c = cptyId,
      AXF_CER_LKP_Account__c = accId,
      AXF_CER_PKL_Role__c = 'SUPPLIER',
      AXF_CER_PKL_Status__c = 'ACTIVE',
      AXF_CER_TXT_EntitySpecificDisplay__c = 'Fornecedor Principal',
      AXF_CER_EXI_RelationshipKey__c = AXF_CLS_IdentityFraming.key(new List<Object>{ 'CER', cptyId, accId, 'SUPPLIER' }),
      AXF_CER_NUM_Version__c = 1
    );
    insert rel;
    return rel;
  }

  private static AXF_OBJ_Contract__c createTestContract(Id accId, Id relId, Id cptyId) {
    AXF_OBJ_Contract__c ctr = new AXF_OBJ_Contract__c(
      AXF_CTR_LKP_Account__c = accId,
      AXF_CTR_LKP_Relationship__c = relId,
      AXF_CTR_LKP_Counterparty__c = cptyId,
      AXF_CTR_TXT_ContractCode__c = 'CTR-TEST-WR',
      AXF_CTR_EXI_ContractKey__c = AXF_CLS_IdentityFraming.key(new List<Object>{ 'CONTRACT', accId, 'CTR-TEST-WR' }),
      AXF_CTR_TXT_Title__c = 'Contrato de Teste WR',
      AXF_CTR_PKL_Lifecycle__c = 'DRAFT',
      AXF_CTR_PKL_Type__c = 'EXPENSE',
      AXF_CTR_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CTR_DAT_StartDate__c = Date.today(),
      AXF_CTR_NUM_Version__c = 1
    );
    insert ctr;
    return ctr;
  }

  private static AXF_OBJ_ContractTermVersion__c createTestTermVersion(Id contractId) {
    AXF_OBJ_ContractTermVersion__c term = new AXF_OBJ_ContractTermVersion__c(
      AXF_CTV_LKP_Contract__c = contractId,
      AXF_CTV_NUM_Revision__c = 1,
      AXF_CTV_PKL_Status__c = 'ACTIVE',
      AXF_CTV_PKL_RemunerationModel__c = 'HOURLY',
      AXF_CTV_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CTV_DAT_EffectiveFrom__c = Date.newInstance(2026, 1, 1),
      AXF_CTV_DAT_EffectiveTo__c = Date.newInstance(2026, 12, 31),
      AXF_CTV_CUR_Rate__c = 150.00,
      AXF_CTV_NUM_HoursQuantity__c = 160,
      AXF_CTV_TXT_CalendarPolicy__c = 'STANDARD_CALENDAR',
      AXF_CTV_TXT_TimeZone__c = 'America/Sao_Paulo',
      AXF_CTV_EXI_TermKey__c = 'TERM-TEST-001',
      AXF_CTV_NUM_Version__c = 1
    );
    insert term;
    return term;
  }

  @IsTest
  static void testRegisterAndReimportIdempotency() {
    Account acc = createTestAccount('Empresa Teste WR');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Prestador WR');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);
    AXF_OBJ_ContractTermVersion__c term = createTestTermVersion(ctr.Id);

    ALT_CLS_WorkRecordService service = new ALT_CLS_WorkRecordService();

    ALT_CLS_WorkRecordService.WorkRecordInputDTO input = new ALT_CLS_WorkRecordService.WorkRecordInputDTO();
    input.contractId = ctr.Id;
    input.termVersionId = term.Id;
    input.startDate = Date.newInstance(2026, 3, 1);
    input.endDate = Date.newInstance(2026, 3, 31);
    input.quantity = 40.0;
    input.rate = 150.0;
    input.currencyIsoCode = 'BRL';
    input.source = 'CSV_IMPORT';
    input.description = 'Desenvolvimento modulo contratos';

    Test.startTest();
    ALT_CLS_WorkRecordService.WorkRecordDetailDTO dto1 = service.registerWorkRecord(input);
    Test.stopTest();

    System.assertNotEquals(null, dto1.workRecordId, 'Deve criar o registro de trabalho');
    System.assertEquals('DRAFT', dto1.status, 'Status inicial deve ser DRAFT');
    System.assertEquals(6000.00, dto1.totalAmount, 'Total deve ser quantidade * taxa');
    System.assertNotEquals(null, dto1.evidenceHash, 'Deve calcular o hash de evidencia');

    // Reimportacao identica nao deve duplicar (AC 1)
    ALT_CLS_WorkRecordService.WorkRecordDetailDTO dto2 = service.registerWorkRecord(input);
    System.assertEquals(dto1.workRecordId, dto2.workRecordId, 'Reimportacao identica deve retornar o mesmo registro sem duplicar');

    List<AXF_OBJ_WorkRecord__c> records = [SELECT Id FROM AXF_OBJ_WorkRecord__c WHERE AXF_WR_LKP_Contract__c = :ctr.Id];
    System.assertEquals(1, records.size(), 'Deve existir exatamente 1 registro no banco');
  }

  @IsTest
  static void testLifecycleSubmitApproveReject() {
    Account acc = createTestAccount('Empresa Lifecycle');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Prestador Lifecycle');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_WorkRecordService service = new ALT_CLS_WorkRecordService();

    ALT_CLS_WorkRecordService.WorkRecordInputDTO input = new ALT_CLS_WorkRecordService.WorkRecordInputDTO();
    input.contractId = ctr.Id;
    input.startDate = Date.newInstance(2026, 4, 1);
    input.endDate = Date.newInstance(2026, 4, 30);
    input.quantity = 20.0;
    input.rate = 100.0;
    input.currencyIsoCode = 'BRL';

    ALT_CLS_WorkRecordService.WorkRecordDetailDTO draft = service.registerWorkRecord(input);

    Test.startTest();
    // 1. Submete
    ALT_CLS_WorkRecordService.WorkRecordDetailDTO submitted = service.submitWorkRecord(draft.workRecordId);
    System.assertEquals('SUBMITTED', submitted.status, 'Deve estar SUBMITTED');

    // 2. Rejeita com motivo
    ALT_CLS_WorkRecordService.WorkRecordDetailDTO rejected = service.decideWorkRecord(submitted.workRecordId, false, 'Horas inconsistentes com apontamento');
    System.assertEquals('REJECTED', rejected.status, 'Deve estar REJECTED');
    System.assertEquals('Horas inconsistentes com apontamento', rejected.decisionReason, 'Deve gravar o motivo');

    // 3. Re-submete apos ajuste
    submitted = service.submitWorkRecord(rejected.workRecordId);
    System.assertEquals('SUBMITTED', submitted.status);

    // 4. Aprova
    ALT_CLS_WorkRecordService.WorkRecordDetailDTO approved = service.decideWorkRecord(submitted.workRecordId, true, 'Horas validadas conforme entregavel');
    Test.stopTest();

    System.assertEquals('APPROVED', approved.status, 'Deve estar APPROVED');
    System.assertEquals(UserInfo.getUserId(), approved.decidedById, 'Deve registrar ator revisor');
    System.assertNotEquals(null, approved.decidedAt, 'Deve registrar instante de decisao');
  }

  @IsTest
  static void testApprovedRecordImmutabilityAndCorrection() {
    Account acc = createTestAccount('Empresa Immutability');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Prestador Immutability');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_WorkRecordService service = new ALT_CLS_WorkRecordService();

    ALT_CLS_WorkRecordService.WorkRecordInputDTO input = new ALT_CLS_WorkRecordService.WorkRecordInputDTO();
    input.contractId = ctr.Id;
    input.startDate = Date.newInstance(2026, 5, 1);
    input.endDate = Date.newInstance(2026, 5, 31);
    input.quantity = 50.0;
    input.rate = 120.0;
    input.currencyIsoCode = 'BRL';

    ALT_CLS_WorkRecordService.WorkRecordDetailDTO created = service.registerWorkRecord(input);
    service.submitWorkRecord(created.workRecordId);
    ALT_CLS_WorkRecordService.WorkRecordDetailDTO approved = service.decideWorkRecord(created.workRecordId, true, 'Aprovado pelo gestor');

    // Tentativa de edicao direta no registro aprovado deve falhar na trigger (AC 2, AC 3)
    Boolean updateFailed = false;
    try {
      update new AXF_OBJ_WorkRecord__c(
        Id = approved.workRecordId,
        AXF_WR_NUM_Quantity__c = 60.0
      );
    } catch (DmlException e) {
      updateFailed = true;
      System.assert(e.getMessage().contains('APPROVED sao auditaveis e imutaveis'), 'Deve conter mensagem de imutabilidade');
    }
    System.assert(updateFailed, 'Edicao direta em registro APPROVED deve ser bloqueada');

    // Tentativa de exclusao direta deve falhar
    Boolean deleteFailed = false;
    try {
      delete new AXF_OBJ_WorkRecord__c(Id = approved.workRecordId);
    } catch (DmlException e) {
      deleteFailed = true;
      System.assert(e.getMessage().contains('nao podem ser excluidos'), 'Deve bloquear exclusao');
    }
    System.assert(deleteFailed, 'Exclusao de APPROVED deve ser bloqueada');

    // Correcao por reversao e novo registro (AC 3)
    Test.startTest();
    ALT_CLS_WorkRecordService.WorkRecordInputDTO repInput = new ALT_CLS_WorkRecordService.WorkRecordInputDTO();
    repInput.contractId = ctr.Id;
    repInput.startDate = Date.newInstance(2026, 5, 1);
    repInput.endDate = Date.newInstance(2026, 5, 31);
    repInput.quantity = 45.0; // Corrigido de 50 para 45
    repInput.rate = 120.0;
    repInput.currencyIsoCode = 'BRL';
    repInput.description = 'Horas ajustadas com desconto de feriado';

    ALT_CLS_WorkRecordService.WorkRecordDetailDTO replacement = service.correctApprovedWorkRecord(
      approved.workRecordId,
      repInput,
      'Ajuste acordado entre partes'
    );
    Test.stopTest();

    // Verifica que o original foi para SUPERSEDED
    AXF_OBJ_WorkRecord__c origDb = [SELECT Id, AXF_WR_PKL_Status__c FROM AXF_OBJ_WorkRecord__c WHERE Id = :approved.workRecordId];
    System.assertEquals('SUPERSEDED', origDb.AXF_WR_PKL_Status__c, 'Registro original deve estar SUPERSEDED');

    // Verifica que o novo registro foi criado referenciando o original
    System.assertEquals(approved.workRecordId, replacement.replacedWorkRecordId, 'Novo registro deve apontar para o substituido');
    System.assertEquals('DRAFT', replacement.status, 'Novo registro corretivo inicia em DRAFT');
    System.assertEquals(5400.00, replacement.totalAmount, '45 * 120 = 5400');
  }

  @IsTest
  static void testAssessmentAndAgendaGating() {
    Account acc = createTestAccount('Empresa Assessment');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Prestador Assessment');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_WorkRecordService service = new ALT_CLS_WorkRecordService();

    Date pStart = Date.newInstance(2026, 6, 1);
    Date pEnd = Date.newInstance(2026, 6, 30);

    // 1. Sem registros: avaliacao deve bloquear publicacao de agenda (AC 4)
    ALT_CLS_WorkRecordService.WorkRecordAssessmentDTO assess1 = service.assessContractWorkRecords(ctr.Id, pStart, pEnd);
    System.assertEquals(false, assess1.isApprovedAndComplete, 'Nao deve permitir sem registros aprovados');
    System.assert(assess1.blockageReason.contains('Nao ha registros de trabalho com status APPROVED'), 'Deve conter explicacao de bloqueio');

    // 2. Registro em rascunho/submetido: ainda incompleto
    ALT_CLS_WorkRecordService.WorkRecordInputDTO input = new ALT_CLS_WorkRecordService.WorkRecordInputDTO();
    input.contractId = ctr.Id;
    input.startDate = pStart;
    input.endDate = pEnd;
    input.quantity = 30.0;
    input.rate = 200.0;
    input.currencyIsoCode = 'BRL';

    ALT_CLS_WorkRecordService.WorkRecordDetailDTO wr = service.registerWorkRecord(input);
    service.submitWorkRecord(wr.workRecordId);

    ALT_CLS_WorkRecordService.WorkRecordAssessmentDTO assess2 = service.assessContractWorkRecords(ctr.Id, pStart, pEnd);
    System.assertEquals(false, assess2.isApprovedAndComplete, 'Registros pendentes devem manter bloqueado');
    System.assert(assess2.blockageReason.contains('pendentes de revisao/aprovacao'), 'Deve alertar pendencias');

    // 3. Aprovado: agora completo e elegivel para apuracao
    service.decideWorkRecord(wr.workRecordId, true, 'Aprovado pelo Diretor');

    ALT_CLS_WorkRecordService.WorkRecordAssessmentDTO assess3 = service.assessContractWorkRecords(ctr.Id, pStart, pEnd);
    System.assertEquals(true, assess3.isApprovedAndComplete, 'Deve estar aprovado e completo');
    System.assertEquals(null, assess3.blockageReason, 'Nao deve ter bloqueio');
    System.assertEquals(30.0, assess3.totalApprovedQuantity, 'Quantidade aprovada');
    System.assertEquals(6000.00, assess3.totalApprovedAmount, 'Valor total aprovado');
  }
}
