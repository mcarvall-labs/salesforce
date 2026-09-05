/**
 * @description Testes unitarios para ALT_CLS_ContractRemunerationService e AXF_TRG_ContractTermVersion (AXF-54, AXF-53).
 * Cobre:
 * 1. Modelos de Remuneracao (MONTHLY, HOURLY, FIXED) e campos incompativeis.
 * 2. Calculo de Cronograma e Conservacao de Total (GF-04, proration, horas).
 * 3. Politica de Calendario e Ausencia (Gating BLOCKED vs ACTIVE).
 * 4. Revisao de TermVersion em Rascunho (AXF-53, AC 1):
 *    - Intervalo semiaberto [inicio, fim), moeda, remuneracao, fuso, renovacao, confianca e conta sugerida.
 *    - Timeline e delta nao dependentes de cor.
 * 5. Ativacao Valida e Imutabilidade (AXF-53, AC 2, AC 3):
 *    - Promocao do Contrato para ACTIVE e vinculo de ActiveTermVersion.
 *    - Fechamento da predecessora na fronteira [inicio_antigo, inicio_novo) e transicao para SUPERSEDED.
 *    - Imutabilidade via trigger (rejeicao de edicao indevida e delete em ACTIVE/SUPERSEDED).
 *    - Rejeicao de retroatividade proibida, sobreposicao e versao concorrente.
 */
@IsTest
private class ALT_CLS_ContractRemunerationServiceTest {

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
      AXF_CTR_TXT_ContractCode__c = 'CTR-TEST-001',
      AXF_CTR_EXI_ContractKey__c = AXF_CLS_IdentityFraming.key(new List<Object>{ 'CONTRACT', accId, 'CTR-TEST-001' }),
      AXF_CTR_TXT_Title__c = 'Contrato de Teste',
      AXF_CTR_PKL_Lifecycle__c = 'DRAFT',
      AXF_CTR_PKL_Type__c = 'EXPENSE',
      AXF_CTR_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CTR_DAT_StartDate__c = Date.today(),
      AXF_CTR_NUM_Version__c = 1
    );
    insert ctr;
    return ctr;
  }

  // --- 1. MODELO MONTHLY: VALIDACAO E CAMPOS INCOMPATIVEIS ---

  @IsTest
  static void testMonthlyModel_Success() {
    Account acc = createTestAccount('Empresa Mes');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Mes');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input.contractId = ctr.Id;
    input.accountId = acc.Id;
    input.remunerationModel = 'MONTHLY';
    input.currencyIsoCode = 'BRL';
    input.effectiveFrom = Date.newInstance(2026, 9, 1);
    input.effectiveTo = Date.newInstance(2027, 8, 31);
    input.rate = 5000.00;
    input.proportionalityPolicy = 'CALENDAR_DAYS';
    input.calendarPolicy = 'BUSINESS_DAYS_BRAZIL';
    input.timeZone = 'America/Sao_Paulo';
    input.renewalPolicy = 'AUTOMATIC';
    input.confidence = 'HIGH';

    Test.startTest();
    ALT_CLS_ContractRemunerationService.OperationResultDTO result = service.saveDraftTermVersion(input);
    Test.stopTest();

    System.assert(result.success, 'Deveria salvar versao de termo mensal com sucesso');
    System.assertEquals('DRAFT', result.status, 'Status inicial deve ser DRAFT');

    AXF_OBJ_ContractTermVersion__c saved = [
      SELECT Id, AXF_CTV_CUR_Rate__c, AXF_CTV_NUM_HoursQuantity__c, AXF_CTV_PKL_RenewalPolicy__c, AXF_CTV_PKL_Confidence__c
      FROM AXF_OBJ_ContractTermVersion__c
      WHERE Id = :result.termVersionId
    ];
    System.assertEquals(5000.00, saved.AXF_CTV_CUR_Rate__c, 'Taxa mensal deve ser gravada');
    System.assertEquals(null, saved.AXF_CTV_NUM_HoursQuantity__c, 'Horas devem ser nulas para mensal');
    System.assertEquals('AUTOMATIC', saved.AXF_CTV_PKL_RenewalPolicy__c, 'Politica de renovacao deve ser gravada');
  }

  @IsTest
  static void testMonthlyModel_IncompatibleFields_Throws() {
    Account acc = createTestAccount('Empresa Mes Inc');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Mes Inc');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input.contractId = ctr.Id;
    input.accountId = acc.Id;
    input.remunerationModel = 'MONTHLY';
    input.currencyIsoCode = 'BRL';
    input.effectiveFrom = Date.newInstance(2026, 9, 1);
    input.rate = 5000.00;
    input.hoursQuantity = 40.0; // Incompativel

    Boolean caught = false;
    try {
      service.saveDraftTermVersion(input);
    } catch (AXF_CLS_ContractException e) {
      caught = true;
      System.assert(e.getMessage().contains('incompativel com o modelo MONTHLY'), 'Mensagem esperada');
    }
    System.assert(caught, 'Deveria rejeitar campo incompativel para modelo MONTHLY');
  }

  // --- 2. MODELO HOURLY E FIXED: VALIDACAO E CAMPOS INCOMPATIVEIS ---

  @IsTest
  static void testHourlyModel_Success_And_IncompatibleFields() {
    Account acc = createTestAccount('Empresa Hora');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Hora');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input.contractId = ctr.Id;
    input.accountId = acc.Id;
    input.remunerationModel = 'HOURLY';
    input.currencyIsoCode = 'BRL';
    input.effectiveFrom = Date.newInstance(2026, 9, 1);
    input.rate = 150.00;
    input.hoursQuantity = 160.0;
    input.calendarPolicy = 'BUSINESS_DAYS_BRAZIL';
    input.timeZone = 'America/Sao_Paulo';

    ALT_CLS_ContractRemunerationService.OperationResultDTO result = service.saveDraftTermVersion(input);
    System.assert(result.success, 'Hourly deve salvar com sucesso');

    input.termVersionId = result.termVersionId;
    input.contractedAmount = 50000.00; // Incompativel com HOURLY

    Boolean caught = false;
    try {
      service.saveDraftTermVersion(input);
    } catch (AXF_CLS_ContractException e) {
      caught = true;
      System.assert(e.getMessage().contains('incompativel com o modelo HOURLY'), 'Mensagem de campo incompativel esperada');
    }
    System.assert(caught, 'Deveria rejeitar contractedAmount para modelo HOURLY');
  }

  @IsTest
  static void testFixedModel_Success_And_IncompatibleFields() {
    Account acc = createTestAccount('Empresa Fixo');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Fixo');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input.contractId = ctr.Id;
    input.accountId = acc.Id;
    input.remunerationModel = 'FIXED';
    input.currencyIsoCode = 'BRL';
    input.effectiveFrom = Date.newInstance(2026, 9, 1);
    input.contractedAmount = 100000.00;
    input.installments = 10;
    input.calendarPolicy = 'STANDARD_CALENDAR';
    input.timeZone = 'America/Sao_Paulo';

    ALT_CLS_ContractRemunerationService.OperationResultDTO result = service.saveDraftTermVersion(input);
    System.assert(result.success, 'Fixed deve salvar com sucesso');

    input.termVersionId = result.termVersionId;
    input.rate = 1000.00; // Incompativel com FIXED

    Boolean caught = false;
    try {
      service.saveDraftTermVersion(input);
    } catch (AXF_CLS_ContractException e) {
      caught = true;
      System.assert(e.getMessage().contains('incompativel com o modelo FIXED'), 'Mensagem esperada');
    }
    System.assert(caught, 'Deveria rejeitar rate para modelo FIXED');
  }

  // --- 3. CALCULO DE CRONOGRAMA E FIXTURE GF-04 ---

  @IsTest
  static void testFixedSchedule_CanonicalGF04_ResidualConservation() {
    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input.contractId = '001000000000001AAA';
    input.remunerationModel = 'FIXED';
    input.currencyIsoCode = 'BRL';
    input.effectiveFrom = Date.newInstance(2026, 9, 1);
    input.contractedAmount = 100.00; // Fixture GF-04
    input.installments = 3;          // 100 / 3 = 33.33, 33.33, 33.34 (residual 0.01)

    Test.startTest();
    ALT_CLS_ContractRemunerationService.ScheduleCalculationResultDTO result = service.calculateSchedule(input);
    Test.stopTest();

    System.assert(result.success, 'Calculo deve ser bem-sucedido');
    System.assert(result.isConserved, 'O total deve ser estritamente conservado');
    System.assertEquals(100.00, result.totalAmount, 'Soma total deve ser 100.00');
    System.assertEquals(0.01, result.totalResidual, 'Residual deve ser de 0.01');
    System.assertEquals(3, result.scheduleItems.size(), 'Devem existir 3 parcelas');

    System.assertEquals(33.33, result.scheduleItems[0].amount, 'Parcela 1: 33.33');
    System.assertEquals(0.00, result.scheduleItems[0].roundingResidual, 'Residual parcela 1: 0.00');

    System.assertEquals(33.33, result.scheduleItems[1].amount, 'Parcela 2: 33.33');
    System.assertEquals(0.00, result.scheduleItems[1].roundingResidual, 'Residual parcela 2: 0.00');

    System.assertEquals(33.34, result.scheduleItems[2].amount, 'Parcela 3 (final): 33.34');
    System.assertEquals(0.01, result.scheduleItems[2].roundingResidual, 'Residual parcela 3: 0.01');
    System.assert(result.scheduleItems[2].isLast, 'Ultima parcela marcada como isLast');
  }

  // --- 4. REVISAO FORMAL DE TERMO (AXF-53, AC 1) ---

  @IsTest
  static void testTermVersionReview_Success() {
    Account acc = createTestAccount('Empresa Review');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Review');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input.contractId = ctr.Id;
    input.accountId = acc.Id;
    input.remunerationModel = 'MONTHLY';
    input.currencyIsoCode = 'BRL';
    input.effectiveFrom = Date.newInstance(2026, 9, 1);
    input.effectiveTo = Date.newInstance(2027, 8, 31);
    input.rate = 12000.00;
    input.proportionalityPolicy = 'CALENDAR_DAYS';
    input.calendarPolicy = 'BUSINESS_DAYS_BRAZIL';
    input.timeZone = 'America/Sao_Paulo';
    input.renewalPolicy = 'AUTOMATIC';
    input.confidence = 'HIGH';

    ALT_CLS_ContractRemunerationService.OperationResultDTO saveRes = service.saveDraftTermVersion(input);

    Test.startTest();
    ALT_CLS_ContractRemunerationService.TermVersionReviewDTO review = service.getTermVersionReview(saveRes.termVersionId, acc.Id);
    Test.stopTest();

    System.assertNotEquals(null, review, 'Review DTO nao deve ser nulo');
    System.assertEquals('[2026-09-01, 2027-08-31)', review.intervalLabel, 'Intervalo semiaberto canonico [inicio, fim)');
    System.assertEquals('AUTOMATIC', review.renewalPolicy, 'Politica de renovacao deve ser retornada');
    System.assertEquals('HIGH', review.confidence, 'Confianca deve ser retornada');
    System.assert(review.remunerationSummary.contains('12000'), 'Resumo deve conter taxa');
    System.assert(!review.timelineLabels.isEmpty(), 'Timeline deve conter rotulos textuais sem depender de cor');
  }

  // --- 5. ATIVACAO, FECHAMENTO DE PREDECESSORA E BLOQUEIO DE CONTRATO (AXF-53, AC 2) ---

  @IsTest
  static void testActivateTermVersion_FirstActivation_PromotesContract() {
    Account acc = createTestAccount('Empresa Ativacao 1');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Ativacao 1');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input.contractId = ctr.Id;
    input.accountId = acc.Id;
    input.remunerationModel = 'MONTHLY';
    input.currencyIsoCode = 'BRL';
    input.effectiveFrom = Date.newInstance(2026, 9, 1);
    input.rate = 8000.00;
    input.calendarPolicy = 'BUSINESS_DAYS_BRAZIL';
    input.timeZone = 'America/Sao_Paulo';

    ALT_CLS_ContractRemunerationService.OperationResultDTO saveRes = service.saveDraftTermVersion(input);

    Test.startTest();
    ALT_CLS_ContractRemunerationService.OperationResultDTO actRes = service.activateTermVersion(saveRes.termVersionId, acc.Id, 1, 1);
    Test.stopTest();

    System.assert(actRes.success, 'Primeira ativacao deve ser realizada com sucesso');
    System.assertEquals('ACTIVE', actRes.status, 'Status deve ser ACTIVE');

    AXF_OBJ_Contract__c updatedCtr = [
      SELECT Id, AXF_CTR_PKL_Lifecycle__c, AXF_CTR_LKP_ActiveTermVersion__c, AXF_CTR_NUM_Version__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :ctr.Id
    ];
    System.assertEquals('ACTIVE', updatedCtr.AXF_CTR_PKL_Lifecycle__c, 'Contrato deve ser promovido para ACTIVE');
    System.assertEquals(saveRes.termVersionId, updatedCtr.AXF_CTR_LKP_ActiveTermVersion__c, 'ActiveTermVersion vinculada');
    System.assertEquals(2, updatedCtr.AXF_CTR_NUM_Version__c, 'Versao do contrato incrementada');
  }

  @IsTest
  static void testActivateTermVersion_SuccessorActivation_ClosesPredecessor() {
    Account acc = createTestAccount('Empresa Sucessao');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Sucessao');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    // Versao 1: R$ 5.000 a partir de 01/09/2026
    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input1 = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input1.contractId = ctr.Id;
    input1.accountId = acc.Id;
    input1.remunerationModel = 'MONTHLY';
    input1.currencyIsoCode = 'BRL';
    input1.effectiveFrom = Date.newInstance(2026, 9, 1);
    input1.rate = 5000.00;
    input1.calendarPolicy = 'BUSINESS_DAYS_BRAZIL';
    input1.timeZone = 'America/Sao_Paulo';

    ALT_CLS_ContractRemunerationService.OperationResultDTO v1 = service.saveDraftTermVersion(input1);
    service.activateTermVersion(v1.termVersionId, acc.Id);

    // Versao 2: R$ 6.000 a partir de 01/01/2027
    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input2 = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input2.contractId = ctr.Id;
    input2.accountId = acc.Id;
    input2.remunerationModel = 'MONTHLY';
    input2.currencyIsoCode = 'BRL';
    input2.effectiveFrom = Date.newInstance(2027, 1, 1);
    input2.rate = 6000.00;
    input2.calendarPolicy = 'BUSINESS_DAYS_BRAZIL';
    input2.timeZone = 'America/Sao_Paulo';

    ALT_CLS_ContractRemunerationService.OperationResultDTO v2 = service.saveDraftTermVersion(input2);

    Test.startTest();
    ALT_CLS_ContractRemunerationService.OperationResultDTO act2 = service.activateTermVersion(v2.termVersionId, acc.Id);
    Test.stopTest();

    System.assert(act2.success, 'Sucessora ativada com sucesso');

    // Verifica fechamento da predecessora
    AXF_OBJ_ContractTermVersion__c pred = [
      SELECT Id, AXF_CTV_PKL_Status__c, AXF_CTV_DAT_EffectiveTo__c, AXF_CTV_LKP_SuccessorTermVersion__c
      FROM AXF_OBJ_ContractTermVersion__c
      WHERE Id = :v1.termVersionId
    ];
    System.assertEquals('SUPERSEDED', pred.AXF_CTV_PKL_Status__c, 'Predecessora deve estar SUPERSEDED');
    System.assertEquals(Date.newInstance(2027, 1, 1), pred.AXF_CTV_DAT_EffectiveTo__c, 'Fronteira semiaberta: final = inicio da sucessora');
    System.assertEquals(v2.termVersionId, pred.AXF_CTV_LKP_SuccessorTermVersion__c, 'Sucessora apontada na predecessora');

    AXF_OBJ_ContractTermVersion__c succ = [
      SELECT Id, AXF_CTV_PKL_Status__c, AXF_CTV_LKP_PredecessorTermVersion__c
      FROM AXF_OBJ_ContractTermVersion__c
      WHERE Id = :v2.termVersionId
    ];
    System.assertEquals('ACTIVE', succ.AXF_CTV_PKL_Status__c, 'Sucessora deve estar ACTIVE');
    System.assertEquals(v1.termVersionId, succ.AXF_CTV_LKP_PredecessorTermVersion__c, 'Predecessora apontada na sucessora');
  }

  // --- 6. IMUTABILIDADE E PROTECAO DE TERMOS ATIVOS E SUPERSEDED (AXF-53, AC 2) ---

  @IsTest
  static void testTriggerImmutability_DirectUpdateOrDelete_Throws() {
    Account acc = createTestAccount('Empresa Imutavel');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Imutavel');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input.contractId = ctr.Id;
    input.accountId = acc.Id;
    input.remunerationModel = 'MONTHLY';
    input.currencyIsoCode = 'BRL';
    input.effectiveFrom = Date.newInstance(2026, 9, 1);
    input.rate = 7000.00;
    input.calendarPolicy = 'BUSINESS_DAYS_BRAZIL';
    input.timeZone = 'America/Sao_Paulo';

    ALT_CLS_ContractRemunerationService.OperationResultDTO v = service.saveDraftTermVersion(input);
    service.activateTermVersion(v.termVersionId, acc.Id);

    AXF_OBJ_ContractTermVersion__c activeTerm = [
      SELECT Id, AXF_CTV_CUR_Rate__c, AXF_CTV_PKL_Status__c
      FROM AXF_OBJ_ContractTermVersion__c
      WHERE Id = :v.termVersionId
    ];

    // 1. Tentar alterar o valor de um termo ACTIVE diretamente via DML
    activeTerm.AXF_CTV_CUR_Rate__c = 9999.00;
    Boolean updateCaught = false;
    try {
      update activeTerm;
    } catch (DmlException e) {
      updateCaught = true;
      System.assert(e.getMessage().contains('imutaveis'), 'Erro de imutabilidade esperado');
    }
    System.assert(updateCaught, 'Trigger deve impedir edicao direta em termo ACTIVE');

    // 2. Tentar excluir um termo ACTIVE
    Boolean deleteCaught = false;
    try {
      delete [SELECT Id FROM AXF_OBJ_ContractTermVersion__c WHERE Id = :v.termVersionId];
    } catch (DmlException e) {
      deleteCaught = true;
      System.assert(e.getMessage().contains('nao podem ser excluidos'), 'Erro de delecao esperado');
    }
    System.assert(deleteCaught, 'Trigger deve impedir exclusao de termo ACTIVE');
  }

  // --- 7. RETROATIVIDADE PROIBIDA, CONCORRENCIA E GATING (AXF-53, AC 3) ---

  @IsTest
  static void testActivateTermVersion_RetroactivityForbidden_Throws() {
    Account acc = createTestAccount('Empresa Retro');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Retro');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    // Termo 1 ativo em 01/09/2026
    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input1 = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input1.contractId = ctr.Id;
    input1.accountId = acc.Id;
    input1.remunerationModel = 'MONTHLY';
    input1.currencyIsoCode = 'BRL';
    input1.effectiveFrom = Date.newInstance(2026, 9, 1);
    input1.rate = 5000.00;
    input1.calendarPolicy = 'BUSINESS_DAYS_BRAZIL';
    input1.timeZone = 'America/Sao_Paulo';

    ALT_CLS_ContractRemunerationService.OperationResultDTO v1 = service.saveDraftTermVersion(input1);
    service.activateTermVersion(v1.termVersionId, acc.Id);

    // Termo 2 querendo iniciar em 01/08/2026 (retroativo a termo ativo)
    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input2 = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input2.contractId = ctr.Id;
    input2.accountId = acc.Id;
    input2.remunerationModel = 'MONTHLY';
    input2.currencyIsoCode = 'BRL';
    input2.effectiveFrom = Date.newInstance(2026, 8, 1);
    input2.rate = 6000.00;
    input2.calendarPolicy = 'BUSINESS_DAYS_BRAZIL';
    input2.timeZone = 'America/Sao_Paulo';

    ALT_CLS_ContractRemunerationService.OperationResultDTO v2 = service.saveDraftTermVersion(input2);

    Boolean caught = false;
    try {
      service.activateTermVersion(v2.termVersionId, acc.Id);
    } catch (AXF_CLS_ContractException e) {
      caught = true;
      System.assert(e.getMessage().contains('Retroatividade proibida'), 'Mensagem de retroatividade esperada: ' + e.getMessage());
    }
    System.assert(caught, 'Deveria bloquear ativacao retroativa');
  }

  @IsTest
  static void testActivateTermVersion_ConcurrencyConflict_Throws() {
    Account acc = createTestAccount('Empresa Conc');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Conc');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input.contractId = ctr.Id;
    input.accountId = acc.Id;
    input.remunerationModel = 'MONTHLY';
    input.currencyIsoCode = 'BRL';
    input.effectiveFrom = Date.newInstance(2026, 9, 1);
    input.rate = 5000.00;
    input.calendarPolicy = 'BUSINESS_DAYS_BRAZIL';
    input.timeZone = 'America/Sao_Paulo';

    ALT_CLS_ContractRemunerationService.OperationResultDTO v = service.saveDraftTermVersion(input);

    Boolean caught = false;
    try {
      // Passa versao esperada do contrato obsoleta (99 ao inves de 1)
      service.activateTermVersion(v.termVersionId, acc.Id, 99, 1);
    } catch (AXF_CLS_ContractException e) {
      caught = true;
      System.assert(e.getMessage().contains('Conflito de concorrencia'), 'Mensagem de conflito esperada');
    }
    System.assert(caught, 'Deveria lancar erro de conflito de concorrencia');
  }

  @IsTest
  static void testCalendarPolicyGating_UncontractedPolicy_SetsBlocked() {
    Account acc = createTestAccount('Empresa Gating');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Gating');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input.contractId = ctr.Id;
    input.accountId = acc.Id;
    input.remunerationModel = 'MONTHLY';
    input.currencyIsoCode = 'BRL';
    input.effectiveFrom = Date.newInstance(2026, 9, 1);
    input.rate = 5000.00;
    input.calendarPolicy = 'LOCAL_CUSTOM_HOLIDAYS'; // Nao contratada
    input.timeZone = 'America/Sao_Paulo';

    ALT_CLS_ContractRemunerationService.OperationResultDTO v = service.saveDraftTermVersion(input);

    Test.startTest();
    ALT_CLS_ContractRemunerationService.OperationResultDTO result = service.activateTermVersion(v.termVersionId, acc.Id);
    Test.stopTest();

    System.assertEquals(false, result.success, 'Ativacao deve ser bloqueada');
    System.assertEquals('BLOCKED', result.status, 'Status deve ser BLOCKED');
    System.assert(result.message.contains('BLOQUEADA'), 'Mensagem de bloqueio esperada');

    AXF_OBJ_ContractTermVersion__c blocked = [
      SELECT Id, AXF_CTV_PKL_Status__c, AXF_CTV_TXT_BlockedReason__c
      FROM AXF_OBJ_ContractTermVersion__c
      WHERE Id = :v.termVersionId
    ];
    System.assertEquals('BLOCKED', blocked.AXF_CTV_PKL_Status__c, 'Status persistido como BLOCKED');
    System.assert(blocked.AXF_CTV_TXT_BlockedReason__c.contains('nao contratada'), 'Motivo registrado');
  }
}
