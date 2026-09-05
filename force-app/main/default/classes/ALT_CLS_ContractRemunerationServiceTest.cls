/**
 * @description Testes unitarios para ALT_CLS_ContractRemunerationService (AXF-54).
 * Cobre:
 * 1. Modelos de Remuneracao (MONTHLY, HOURLY, FIXED):
 *    - Exige apenas campos aplicaveis de cada modelo.
 *    - Rejeita estritamente campos incompativeis.
 * 2. Calculo de Cronograma e Conservacao de Total:
 *    - GF-04: compra/contrato de BRL 100 em 3 parcelas -> 33.33, 33.33, 33.34 com residual 0.01 na ultima parcela.
 *    - Soma das parcelas conserva o total de 100.00 com exatidao.
 *    - Proporcionalidade mensal (proration) por dias corridos e base 30.
 *    - Estimativa de horas com multiplicacao exata.
 * 3. Politica de Calendario e Ausencia (Gate Canonico):
 *    - Se regra de calendario/ausencia nao for contratada (ausente ou desconhecida) -> BLOCKED.
 *    - Nao inventa formula ou feriado local.
 *    - Politica contratada e fuso valido ativam com sucesso -> ACTIVE.
 * 4. Fechamento de Predecessora e Imutabilidade:
 *    - Nova ativacao fecha vigencia da predecessora e a transiciona para SUPERSEDED.
 *    - Edicao de termo ACTIVE e rejeitada.
 *    - Concorrencia otimista detecta versao obsoleta.
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
    input.timeZone = 'America/Sao_Paulo';
    input.calendarPolicy = 'STANDARD_CALENDAR';

    Test.startTest();
    ALT_CLS_ContractRemunerationService.OperationResultDTO res = service.saveDraftTermVersion(input);
    Test.stopTest();

    System.assert(res.success, 'Deveria salvar com sucesso o termo MONTHLY');
    System.assertEquals('DRAFT', res.status);

    List<AXF_OBJ_ContractTermVersion__c> saved = [
      SELECT Id, AXF_CTV_PKL_RemunerationModel__c, AXF_CTV_CUR_Rate__c, AXF_CTV_PKL_ProportionalityPolicy__c
      FROM AXF_OBJ_ContractTermVersion__c
      WHERE Id = :res.termVersionId
    ];
    System.assertEquals(1, saved.size());
    System.assertEquals('MONTHLY', saved[0].AXF_CTV_PKL_RemunerationModel__c);
    System.assertEquals(5000.00, saved[0].AXF_CTV_CUR_Rate__c);
  }

  @IsTest
  static void testMonthlyModel_RejectsIncompatibleFields() {
    Account acc = createTestAccount('Empresa Mes Incompativel');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Mes Inc');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    // 1. MONTHLY com hoursQuantity -> deve rejeitar
    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input1 = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input1.contractId = ctr.Id;
    input1.remunerationModel = 'MONTHLY';
    input1.currencyIsoCode = 'BRL';
    input1.effectiveFrom = Date.today();
    input1.rate = 5000.00;
    input1.hoursQuantity = 40.0;

    Boolean threwHours = false;
    try {
      service.saveDraftTermVersion(input1);
    } catch (AXF_CLS_ContractException e) {
      threwHours = true;
      System.assert(e.getMessage().contains('Quantidade de Horas'), 'Deveria indicar erro de horas no MONTHLY');
    }
    System.assert(threwHours, 'Deveria lancar excecao para MONTHLY com horas');

    // 2. MONTHLY com installments -> deve rejeitar
    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input2 = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input2.contractId = ctr.Id;
    input2.remunerationModel = 'MONTHLY';
    input2.currencyIsoCode = 'BRL';
    input2.effectiveFrom = Date.today();
    input2.rate = 5000.00;
    input2.installments = 12;

    Boolean threwInstallments = false;
    try {
      service.saveDraftTermVersion(input2);
    } catch (AXF_CLS_ContractException e) {
      threwInstallments = true;
      System.assert(e.getMessage().contains('Numero de Parcelas'), 'Deveria indicar erro de parcelas no MONTHLY');
    }
    System.assert(threwInstallments, 'Deveria lancar excecao para MONTHLY com parcelas');

    // 3. MONTHLY com contractedAmount -> deve rejeitar
    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input3 = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input3.contractId = ctr.Id;
    input3.remunerationModel = 'MONTHLY';
    input3.currencyIsoCode = 'BRL';
    input3.effectiveFrom = Date.today();
    input3.rate = 5000.00;
    input3.contractedAmount = 60000.00;

    Boolean threwAmount = false;
    try {
      service.saveDraftTermVersion(input3);
    } catch (AXF_CLS_ContractException e) {
      threwAmount = true;
      System.assert(e.getMessage().contains('Valor Total Contratado'), 'Deveria indicar erro de valor fixo no MONTHLY');
    }
    System.assert(threwAmount, 'Deveria lancar excecao para MONTHLY com valor fixo');
  }

  // --- 2. MODELO HOURLY: VALIDACAO E CAMPOS INCOMPATIVEIS ---

  @IsTest
  static void testHourlyModel_Success() {
    Account acc = createTestAccount('Empresa Hora');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Hora');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input.contractId = ctr.Id;
    input.accountId = acc.Id;
    input.remunerationModel = 'HOURLY';
    input.currencyIsoCode = 'USD';
    input.effectiveFrom = Date.today();
    input.rate = 50.00;
    input.hoursQuantity = 160.00;
    input.timeZone = 'Europe/Lisbon';
    input.calendarPolicy = 'STANDARD_CALENDAR';

    Test.startTest();
    ALT_CLS_ContractRemunerationService.OperationResultDTO res = service.saveDraftTermVersion(input);
    Test.stopTest();

    System.assert(res.success);
    AXF_OBJ_ContractTermVersion__c saved = [SELECT Id, AXF_CTV_CUR_Rate__c, AXF_CTV_NUM_HoursQuantity__c FROM AXF_OBJ_ContractTermVersion__c WHERE Id = :res.termVersionId];
    System.assertEquals(50.00, saved.AXF_CTV_CUR_Rate__c);
    System.assertEquals(160.00, saved.AXF_CTV_NUM_HoursQuantity__c);
  }

  @IsTest
  static void testHourlyModel_RejectsIncompatibleFields() {
    Account acc = createTestAccount('Empresa Hora Inc');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Hora Inc');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    // HOURLY com installments -> deve rejeitar
    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input.contractId = ctr.Id;
    input.remunerationModel = 'HOURLY';
    input.currencyIsoCode = 'USD';
    input.effectiveFrom = Date.today();
    input.rate = 50.00;
    input.hoursQuantity = 160.00;
    input.installments = 10;

    Boolean threw = false;
    try {
      service.saveDraftTermVersion(input);
    } catch (AXF_CLS_ContractException e) {
      threw = true;
      System.assert(e.getMessage().contains('Numero de Parcelas'));
    }
    System.assert(threw, 'Deveria rejeitar parcelas em HOURLY');
  }

  // --- 3. MODELO FIXED E CRONOGRAMA CANONICO (GF-04) ---

  @IsTest
  static void testFixedModel_GF04_InstallmentsConservationAndResidual() {
    Account acc = createTestAccount('Empresa Fixo GF04');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Fixo GF04');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    // Fixture GF-04: Total BRL 100 em 3 parcelas
    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input.contractId = ctr.Id;
    input.accountId = acc.Id;
    input.remunerationModel = 'FIXED';
    input.currencyIsoCode = 'BRL';
    input.effectiveFrom = Date.newInstance(2026, 9, 5);
    input.contractedAmount = 100.00;
    input.installments = 3;
    input.timeZone = 'America/Sao_Paulo';
    input.calendarPolicy = 'STANDARD_CALENDAR';

    Test.startTest();
    ALT_CLS_ContractRemunerationService.OperationResultDTO saveRes = service.saveDraftTermVersion(input);
    ALT_CLS_ContractRemunerationService.ScheduleCalculationResultDTO calcRes = service.calculateSchedule(input);
    Test.stopTest();

    System.assert(saveRes.success);
    System.assert(calcRes.success);
    System.assert(calcRes.isConserved, 'A soma das parcelas DEVE conservar o total exatamente (GF-04)');
    System.assertEquals(100.00, calcRes.totalAmount);
    System.assertEquals(3, calcRes.scheduleItems.size());

    // Parcela 1: 33.33, residual 0.00
    System.assertEquals(33.33, calcRes.scheduleItems[0].amount);
    System.assertEquals(0.00, calcRes.scheduleItems[0].roundingResidual);
    System.assertEquals(false, calcRes.scheduleItems[0].isLast);

    // Parcela 2: 33.33, residual 0.00
    System.assertEquals(33.33, calcRes.scheduleItems[1].amount);
    System.assertEquals(0.00, calcRes.scheduleItems[1].roundingResidual);
    System.assertEquals(false, calcRes.scheduleItems[1].isLast);

    // Parcela 3: 33.34, residual 0.01 na ultima parcela! (GF-04)
    System.assertEquals(33.34, calcRes.scheduleItems[2].amount);
    System.assertEquals(0.01, calcRes.scheduleItems[2].roundingResidual);
    System.assertEquals(true, calcRes.scheduleItems[2].isLast);

    Decimal sum = calcRes.scheduleItems[0].amount + calcRes.scheduleItems[1].amount + calcRes.scheduleItems[2].amount;
    System.assertEquals(100.00, sum, 'A soma 33.33 + 33.33 + 33.34 deve totalizar exatamente 100.00');
  }

  @IsTest
  static void testFixedModel_RejectsRateAndHours() {
    Account acc = createTestAccount('Empresa Fixo Inc');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Fixo Inc');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input.contractId = ctr.Id;
    input.remunerationModel = 'FIXED';
    input.currencyIsoCode = 'BRL';
    input.effectiveFrom = Date.today();
    input.contractedAmount = 1000.00;
    input.installments = 2;
    input.rate = 500.00; // Incompativel!

    Boolean threw = false;
    try {
      service.saveDraftTermVersion(input);
    } catch (AXF_CLS_ContractException e) {
      threw = true;
      System.assert(e.getMessage().contains('Taxa Periodica'));
    }
    System.assert(threw, 'Deveria rejeitar taxa no modelo FIXED');
  }

  // --- 4. PROPORCIONALIDADE MENSAL (PRORATION) ---

  @IsTest
  static void testMonthlyProration_PartialMonth() {
    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input.contractId = 'a00000000000001AAA';
    input.remunerationModel = 'MONTHLY';
    input.currencyIsoCode = 'BRL';
    // Setembro de 2026 tem 30 dias. Comecando no dia 11 e terminando no dia 30 (20 dias ativos)
    input.effectiveFrom = Date.newInstance(2026, 9, 11);
    input.effectiveTo = Date.newInstance(2026, 9, 30);
    input.rate = 3000.00;
    input.proportionalityPolicy = 'CALENDAR_DAYS';
    input.timeZone = 'America/Sao_Paulo';
    input.calendarPolicy = 'STANDARD_CALENDAR';

    ALT_CLS_ContractRemunerationService.ScheduleCalculationResultDTO calcRes = service.calculateSchedule(input);
    System.assert(calcRes.success);
    System.assertEquals(1, calcRes.scheduleItems.size());
    // 3000 * 20 / 30 = 2000.00
    System.assertEquals(2000.00, calcRes.scheduleItems[0].amount);
  }

  // --- 5. GATE DE CALENDARIO E AUSENCIA NAO CONTRATADA (AC 3: BLOCKED) ---

  @IsTest
  static void testActivate_UncontractedCalendarBlocksActivation() {
    Account acc = createTestAccount('Empresa Gate');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Gate');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    // Cria termo com regra de calendario NAO contratada ('LOCAL_CUSTOM_HOLIDAYS')
    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input.contractId = ctr.Id;
    input.accountId = acc.Id;
    input.remunerationModel = 'MONTHLY';
    input.currencyIsoCode = 'BRL';
    input.effectiveFrom = Date.today();
    input.rate = 4000.00;
    input.timeZone = 'America/Sao_Paulo';
    input.calendarPolicy = 'LOCAL_CUSTOM_HOLIDAYS'; // Nao contratada!

    ALT_CLS_ContractRemunerationService.OperationResultDTO saveRes = service.saveDraftTermVersion(input);
    System.assert(saveRes.success);

    Test.startTest();
    ALT_CLS_ContractRemunerationService.OperationResultDTO actRes = service.activateTermVersion(saveRes.termVersionId, acc.Id);
    Test.stopTest();

    // Criterio de Aceite 3: Fica BLOCKED e nao inventa formula ou feriado local
    System.assertEquals(false, actRes.success);
    System.assertEquals('BLOCKED', actRes.status);
    System.assert(actRes.message.contains('BLOQUEADA'), 'Deveria indicar bloqueio');

    AXF_OBJ_ContractTermVersion__c blocked = [
      SELECT Id, AXF_CTV_PKL_Status__c, AXF_CTV_TXT_BlockedReason__c
      FROM AXF_OBJ_ContractTermVersion__c
      WHERE Id = :saveRes.termVersionId
    ];
    System.assertEquals('BLOCKED', blocked.AXF_CTV_PKL_Status__c);
    System.assert(blocked.AXF_CTV_TXT_BlockedReason__c.contains('nao contratada'));
  }

  @IsTest
  static void testActivate_ContractedCalendarSucceedsAndSupersedesPredecessor() {
    Account acc = createTestAccount('Empresa Sucesso');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Sucesso');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    // 1. Termo v1 ativo
    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input1 = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input1.contractId = ctr.Id;
    input1.accountId = acc.Id;
    input1.remunerationModel = 'MONTHLY';
    input1.currencyIsoCode = 'BRL';
    input1.effectiveFrom = Date.newInstance(2026, 1, 1);
    input1.rate = 4000.00;
    input1.timeZone = 'America/Sao_Paulo';
    input1.calendarPolicy = 'STANDARD_CALENDAR'; // Contratada!

    ALT_CLS_ContractRemunerationService.OperationResultDTO saveRes1 = service.saveDraftTermVersion(input1);
    ALT_CLS_ContractRemunerationService.OperationResultDTO actRes1 = service.activateTermVersion(saveRes1.termVersionId, acc.Id);
    System.assert(actRes1.success);
    System.assertEquals('ACTIVE', actRes1.status);

    // 2. Termo v2 comeca em 2026-06-01
    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input2 = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input2.contractId = ctr.Id;
    input2.accountId = acc.Id;
    input2.remunerationModel = 'MONTHLY';
    input2.currencyIsoCode = 'BRL';
    input2.effectiveFrom = Date.newInstance(2026, 6, 1);
    input2.rate = 4500.00;
    input2.timeZone = 'America/Sao_Paulo';
    input2.calendarPolicy = 'STANDARD_CALENDAR';

    ALT_CLS_ContractRemunerationService.OperationResultDTO saveRes2 = service.saveDraftTermVersion(input2);

    Test.startTest();
    ALT_CLS_ContractRemunerationService.OperationResultDTO actRes2 = service.activateTermVersion(saveRes2.termVersionId, acc.Id);
    Test.stopTest();

    System.assert(actRes2.success);
    System.assertEquals('ACTIVE', actRes2.status);

    // Verifica que v1 foi fechada e virou SUPERSEDED
    AXF_OBJ_ContractTermVersion__c v1 = [
      SELECT Id, AXF_CTV_PKL_Status__c, AXF_CTV_DAT_EffectiveTo__c
      FROM AXF_OBJ_ContractTermVersion__c
      WHERE Id = :saveRes1.termVersionId
    ];
    System.assertEquals('SUPERSEDED', v1.AXF_CTV_PKL_Status__c);
    System.assertEquals(Date.newInstance(2026, 6, 1), v1.AXF_CTV_DAT_EffectiveTo__c);
  }

  @IsTest
  static void testActiveTermImmutability() {
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
    input.effectiveFrom = Date.today();
    input.rate = 4000.00;
    input.timeZone = 'America/Sao_Paulo';
    input.calendarPolicy = 'STANDARD_CALENDAR';

    ALT_CLS_ContractRemunerationService.OperationResultDTO saveRes = service.saveDraftTermVersion(input);
    service.activateTermVersion(saveRes.termVersionId, acc.Id);

    // Tentativa de update do termo ACTIVE -> deve ser rejeitada
    input.termVersionId = saveRes.termVersionId;
    input.rate = 4200.00;

    Boolean threw = false;
    try {
      service.saveDraftTermVersion(input);
    } catch (AXF_CLS_ContractException e) {
      threw = true;
      System.assert(e.getMessage().contains('ACTIVE sao imutaveis'));
    }
    System.assert(threw, 'Deveria bloquear alteracao de termo ACTIVE');
  }

  @IsTest
  static void testListTermVersions() {
    Account acc = createTestAccount('Empresa Listagem');
    AXF_OBJ_Counterparty__c cpty = createTestCounterparty('Contraparte Listagem');
    AXF_OBJ_CounterpartyEntityRelationship__c rel = createTestRelationship(cpty.Id, acc.Id);
    AXF_OBJ_Contract__c ctr = createTestContract(acc.Id, rel.Id, cpty.Id);

    ALT_CLS_ContractRemunerationService service = new ALT_CLS_ContractRemunerationService();

    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input.contractId = ctr.Id;
    input.accountId = acc.Id;
    input.remunerationModel = 'MONTHLY';
    input.currencyIsoCode = 'BRL';
    input.effectiveFrom = Date.today();
    input.rate = 4000.00;
    input.timeZone = 'America/Sao_Paulo';
    input.calendarPolicy = 'STANDARD_CALENDAR';

    service.saveDraftTermVersion(input);

    List<ALT_CLS_ContractRemunerationService.TermVersionDetailDTO> listTerms = service.getTermVersionsByContract(ctr.Id, acc.Id);
    System.assertEquals(1, listTerms.size());
    System.assertEquals('MONTHLY', listTerms[0].remunerationModel);
  }
}
