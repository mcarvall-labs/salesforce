/**
 * @description Testes unitarios de ALT_CLS_EvidenceQueryService (AXF-49, G7 fechado).
 * Cobre: matriz de cobertura (integrados COVERED + lacunas GAP honestas), consulta read-only
 * de CAS/FXS/FxC/FxSettlement/EXR, agregacao por FinancialTransaction, tipo invalido/null e
 * negacao sem vazar existencia (registro ausente -> denied). Dados ficticios; testes
 * proporcionais ao delta.
 */
@IsTest
private class ALT_CLS_EvidenceQueryServiceTest {
  private static Account makeAccount(String name) {
    Account acc = new Account(Name = name);
    Id bRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('AXF_Business')
      ?.getRecordTypeId();
    if (bRtId != null) {
      acc.RecordTypeId = bRtId;
    }
    insert acc;
    return acc;
  }

  private static AXF_OBJ_Counterparty__c makeCounterparty(String name) {
    AXF_OBJ_Counterparty__c cpty = new AXF_OBJ_Counterparty__c(
      Name = name,
      AXF_CPTY_TXT_DisplayName__c = name,
      AXF_CPTY_TXT_LegalName__c = name + ' LTDA',
      AXF_CPTY_TXT_Country__c = 'BR',
      AXF_CPTY_PKL_Kind__c = 'ORGANIZATION',
      AXF_CPTY_PKL_Status__c = 'ACTIVE',
      AXF_CPTY_EXI_CounterpartyKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'CPTY', name + ' LTDA', 'BR' }
      ),
      AXF_CPTY_NUM_Version__c = 1
    );
    insert cpty;
    return cpty;
  }

  private static AXF_OBJ_CounterpartyEntityRelationship__c makeRelationship(
    Id cptyId,
    Id accId
  ) {
    AXF_OBJ_CounterpartyEntityRelationship__c rel = new AXF_OBJ_CounterpartyEntityRelationship__c(
      AXF_CER_LKP_Counterparty__c = cptyId,
      AXF_CER_LKP_Account__c = accId,
      AXF_CER_PKL_Role__c = 'SUPPLIER',
      AXF_CER_PKL_Status__c = 'ACTIVE',
      AXF_CER_TXT_EntitySpecificDisplay__c = 'Fornecedor Principal',
      AXF_CER_EXI_RelationshipKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'CER', cptyId, accId, 'SUPPLIER' }
      ),
      AXF_CER_NUM_Version__c = 1
    );
    insert rel;
    return rel;
  }

  private static Id makeContract(Account acc) {
    ALT_CLS_ContractService.ContractInputDTO input = new ALT_CLS_ContractService.ContractInputDTO();
    input.accountId = acc.Id;
    input.relationshipId = makeRelationship(
        makeCounterparty('Fornecedor ' + acc.Name).Id,
        acc.Id
      )
      .Id;
    input.contractCode = 'CTR-' + Datetime.now().getTime() + '-' + acc.Name;
    input.title = 'Contrato de teste AXF-49';
    input.contractType = 'EXPENSE';
    input.currencyIsoCode = 'BRL';
    input.startDate = Date.today().addMonths(-1);
    input.endDate = Date.today().addMonths(11);
    ALT_CLS_ContractService service = new ALT_CLS_ContractService();
    ALT_CLS_ContractService.OperationResultDTO res = service.createDraftContract(
      input
    );
    Assert.isTrue(res.success, 'Contrato de teste criado.');
    return res.contractId;
  }

  private static AXF_OBJ_ContractTermVersion__c makeActiveTerm(
    Id contractId,
    Decimal revision
  ) {
    AXF_OBJ_ContractTermVersion__c term = new AXF_OBJ_ContractTermVersion__c(
      AXF_CTV_LKP_Contract__c = contractId,
      AXF_CTV_NUM_Revision__c = revision,
      AXF_CTV_PKL_Status__c = 'ACTIVE',
      AXF_CTV_PKL_RemunerationModel__c = 'FIXED',
      AXF_CTV_CUR_ContractedAmount__c = 1000,
      AXF_CTV_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CTV_DAT_EffectiveFrom__c = Date.today().addMonths(-1),
      AXF_CTV_NUM_Version__c = 1
    );
    insert term;
    return term;
  }

  private static AXF_OBJ_FinancialTransaction__c makeContractOccurrence(
    Account acc,
    String groupKey,
    Decimal sequence,
    Boolean withPlanHash
  ) {
    AXF_OBJ_FinancialTransaction__c ftx = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = acc.Id,
      AXF_FTX_NUM_Magnitude__c = 1000,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = Date.today(),
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_TXT_ScheduleGroupKey__c = groupKey,
      AXF_FTX_NUM_Sequence__c = sequence,
      AXF_FTX_EXI_ClientRequestId__c = 'ftx-' +
        Datetime.now().getTime() +
        '-' +
        groupKey +
        '-' +
        sequence
    );
    if (withPlanHash) {
      ftx.AXF_FTX_EXI_PlanIdentityHash__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'ftx-plan-v1', groupKey, sequence }
      );
    }
    insert ftx;
    return ftx;
  }

  private static Id makeCasSnapshot(Account acc, String groupKey) {
    Id contractId = makeContract(acc);
    AXF_OBJ_ContractTermVersion__c term = makeActiveTerm(contractId, 1);
    AXF_OBJ_FinancialTransaction__c ftx = makeContractOccurrence(
      acc,
      groupKey,
      1,
      true
    );
    ALT_CLS_ContractSnapshotService service = new ALT_CLS_ContractSnapshotService();
    ALT_CLS_ContractSnapshotService.SnapshotInputDTO input = new ALT_CLS_ContractSnapshotService.SnapshotInputDTO();
    input.financialTransactionId = ftx.Id;
    input.termVersionId = term.Id;
    ALT_CLS_ContractSnapshotService.SnapshotResultDTO result = service.applyToOccurrence(
      input
    );
    Assert.isTrue(result.created, 'CAS criado para consulta.');
    return result.snapshotId;
  }

  private static AXF_OBJ_FinancialTransaction__c makeFtx(
    Account acc,
    Decimal magnitude,
    String iso
  ) {
    AXF_OBJ_FinancialTransaction__c ftx = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = acc.Id,
      AXF_FTX_NUM_Magnitude__c = magnitude,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = iso,
      AXF_FTX_DAT_PurchaseDate__c = Date.today(),
      AXF_FTX_PKL_Status__c = 'CONFIRMED',
      AXF_FTX_EXI_ClientRequestId__c = 'evq-ftx-' + Datetime.now().getTime()
    );
    insert ftx;
    return ftx;
  }

  private static AXF_OBJ_ExchangeRate__c makeRate(
    String baseIso,
    String quoteIso,
    Decimal rate
  ) {
    AXF_OBJ_ExchangeRate__c exr = new AXF_OBJ_ExchangeRate__c(
      AXF_EXR_TXT_BaseCurrency__c = baseIso,
      AXF_EXR_TXT_QuoteCurrency__c = quoteIso,
      AXF_EXR_NUM_Rate__c = rate,
      AXF_EXR_PKL_Side__c = 'SELL',
      AXF_EXR_TXT_Provider__c = 'BCB_PTAX',
      AXF_EXR_DT_EffectiveDateTime__c = System.now().addHours(-1),
      AXF_EXR_EXI_RateKey__c = 'r-' +
        Datetime.now().getTime() +
        '-' +
        baseIso +
        quoteIso
    );
    insert exr;
    return exr;
  }

  private static Id makeSettlement(Account acc, String direction) {
    ALT_CLS_FxSettlementService.DraftInputDTO input = new ALT_CLS_FxSettlementService.DraftInputDTO();
    input.accountId = acc.Id;
    input.direction = direction;
    input.sourceCurrency = 'USD';
    input.targetCurrency = 'BRL';
    input.deliveredSource = 1000;
    input.effectiveRate = 5.0;
    input.grossTargetAmount = 5000;
    input.valueDate = Date.today();
    input.operationKey =
      'fxt-evq-' +
      Datetime.now().getTime() +
      '-' +
      direction;
    ALT_CLS_FxSettlementService service = new ALT_CLS_FxSettlementService();
    return service.createDraft(input).settlementId;
  }

  private static Id makeCharge(Id settlementId) {
    ALT_CLS_FxChargeService.ChargeInputDTO input = new ALT_CLS_FxChargeService.ChargeInputDTO();
    input.settlementId = settlementId;
    input.chargeType = 'FEE';
    input.treatment = 'DEDUCTED_TARGET';
    input.magnitude = 38;
    input.currencyIso = 'BRL';
    input.recognitionAuthority = 'DERIVED_CONTRIBUTION';
    input.contributionKey = 'ctrb-evq-1';
    input.evidenceHash = 'ev-' + Datetime.now().getTime();
    ALT_CLS_FxChargeService service = new ALT_CLS_FxChargeService();
    return service.createCharge(input).chargeId;
  }

  @IsTest
  static void coverageMatrix_ReportsCoveredAndGaps() {
    List<ALT_CLS_EvidenceQueryService.CoverageRowDTO> rows = ALT_CLS_EvidenceQueryService.evidenceCoverage();
    Assert.areEqual(9, rows.size(), 'Matriz G7-2 com nove eventos declarados.');

    Map<String, ALT_CLS_EvidenceQueryService.CoverageRowDTO> byKey = new Map<String, ALT_CLS_EvidenceQueryService.CoverageRowDTO>();
    for (ALT_CLS_EvidenceQueryService.CoverageRowDTO r : rows) {
      byKey.put(r.eventKey, r);
    }

    Assert.areEqual(
      ALT_CLS_EvidenceQueryService.COVERED_IMMUTABLE,
      byKey.get('CONTRACT_APPLICATION').coverage
    );
    Assert.areEqual(
      ALT_CLS_EvidenceQueryService.COVERED_IMMUTABLE,
      byKey.get('FX_MATERIAL_CONVERSION').coverage
    );
    Assert.areEqual(
      ALT_CLS_EvidenceQueryService.COVERED_IMMUTABLE,
      byKey.get('FX_CHARGE').coverage
    );
    Assert.areEqual(
      ALT_CLS_EvidenceQueryService.GAP_NOT_INTEGRATED,
      byKey.get('RECONCILIATION').coverage,
      'Reconciliacao ainda nao integrada: GAP honesto, sem auditoria ficticia.'
    );
    Assert.areEqual(
      ALT_CLS_EvidenceQueryService.GAP_NOT_INTEGRATED,
      byKey.get('REVIEW_RESOLUTION').coverage,
      'ReviewItem (AD-41) ainda nao integrado: GAP honesto.'
    );
    Assert.areEqual(
      ALT_CLS_EvidenceQueryService.GAP_NOT_INTEGRATED,
      byKey.get('CALCULATION_DECISION').coverage
    );
    Assert.areEqual(
      ALT_CLS_EvidenceQueryService.GAP_NOT_INTEGRATED,
      byKey.get('BILLING_ISSUANCE').coverage
    );
    Assert.isTrue(
      byKey.get('CONTRACT_APPLICATION').actorAvailable &&
        byKey.get('CONTRACT_APPLICATION').instantAvailable &&
        byKey.get('CONTRACT_APPLICATION').sourceAvailable &&
        byKey.get('CONTRACT_APPLICATION').reasonAvailable &&
        byKey.get('CONTRACT_APPLICATION').priorStateAvailable,
      'Matriz de CAS identifica ator/instante/fonte/motivo/estado anterior.'
    );
  }

  @IsTest
  static void queryCas_ReturnsImmutableEvidence() {
    Account acc = makeAccount('Titular EVQ-CAS');
    Id casId = makeCasSnapshot(acc, 'gk-cas');

    ALT_CLS_EvidenceQueryService.QueryResultDTO out = ALT_CLS_EvidenceQueryService.queryEvidenceForRecord(
      casId
    );

    Assert.isTrue(out.found, 'CAS consultado.');
    Assert.isFalse(out.denied == true, 'Sem negacao para leitor autorizado.');
    Assert.areEqual(1, out.entries.size());
    ALT_CLS_EvidenceQueryService.EvidenceEntryDTO e = out.entries[0];
    Assert.areEqual('CONTRACT_APPLICATION', e.eventKey);
    Assert.areEqual(
      'AXF_OBJ_ContractApplicationSnapshot__c',
      e.evidenceObjectApi
    );
    Assert.areEqual(ALT_CLS_EvidenceQueryService.COVERED_IMMUTABLE, e.coverage);
    Assert.isNotNull(e.actorUserId, 'Ator identificado.');
    Assert.isNotNull(e.instant, 'Instante identificado.');
    Assert.isNotNull(e.sourceLabel, 'Fonte (identity hash) identificada.');
    Assert.areEqual('DEFAULTED (sem override)', e.reasonLabel);
  }

  @IsTest
  static void queryEvidenceForFinancialTransaction_AggregatesFxs() {
    Account acc = makeAccount('Titular EVQ-FTX');
    AXF_OBJ_FinancialTransaction__c ftx = makeFtx(acc, 100, 'USD');
    makeRate('USD', 'BRL', 5.05);

    ALT_CLS_FxConversionService service = new ALT_CLS_FxConversionService();
    ALT_CLS_FxConversionService.ConversionInputDTO input = new ALT_CLS_FxConversionService.ConversionInputDTO();
    input.targetType = 'FINANCIAL_TRANSACTION';
    input.targetId = ftx.Id;
    input.purpose = 'RECOGNITION';
    input.reportingIso = 'BRL';
    input.side = 'SELL';
    input.policyVersion = 'FX-POLICY-1.0.0';
    input.roundingPolicy = 'HALF_UP_2';
    ALT_CLS_FxConversionService.ConversionResultDTO result = service.applyConversion(
      input
    );
    Assert.isTrue(result.converted, 'FXS criado para consulta agregada.');

    ALT_CLS_EvidenceQueryService.QueryResultDTO out = ALT_CLS_EvidenceQueryService.queryEvidenceForFinancialTransaction(
      ftx.Id
    );

    Assert.isTrue(out.found, 'Evidencias encontradas para o FTX.');
    Boolean hasFxs = false;
    for (ALT_CLS_EvidenceQueryService.EvidenceEntryDTO e : out.entries) {
      if (e.eventKey == 'FX_MATERIAL_CONVERSION') {
        hasFxs = true;
        Assert.areEqual(
          ALT_CLS_EvidenceQueryService.COVERED_IMMUTABLE,
          e.coverage
        );
      }
    }
    Assert.isTrue(hasFxs, 'FXS agregado na consulta por FTX.');
  }

  @IsTest
  static void querySettlementAndCharge_ReturnsEvidence() {
    Account acc = makeAccount('Titular EVQ-FXT');
    Id settlementId = makeSettlement(acc, 'INBOUND');

    ALT_CLS_EvidenceQueryService.QueryResultDTO fxt = ALT_CLS_EvidenceQueryService.queryEvidenceForRecord(
      settlementId
    );
    Assert.isTrue(fxt.found, 'Settlement consultado.');
    Assert.areEqual('FX_SETTLEMENT', fxt.entries[0].eventKey);

    Id chargeId = makeCharge(settlementId);
    ALT_CLS_EvidenceQueryService.QueryResultDTO fxc = ALT_CLS_EvidenceQueryService.queryEvidenceForRecord(
      chargeId
    );
    Assert.isTrue(fxc.found, 'Charge consultada.');
    Assert.areEqual('FX_CHARGE', fxc.entries[0].eventKey);
    Assert.isNotNull(fxc.entries[0].actorUserId);
    Assert.isNotNull(fxc.entries[0].sourceLabel);
  }

  @IsTest
  static void queryExchangeRate_ReturnsNativeEvidence() {
    AXF_OBJ_ExchangeRate__c exr = makeRate('USD', 'BRL', 5.05);

    ALT_CLS_EvidenceQueryService.QueryResultDTO out = ALT_CLS_EvidenceQueryService.queryEvidenceForRecord(
      exr.Id
    );

    Assert.isTrue(out.found);
    Assert.areEqual('RATE_EVIDENCE', out.entries[0].eventKey);
    Assert.areEqual(
      ALT_CLS_EvidenceQueryService.COVERED_NATIVE,
      out.entries[0].coverage
    );
    Assert.areEqual('BCB_PTAX', out.entries[0].sourceLabel);
  }

  @IsTest
  static void queryEvidence_UnsupportedType_Throws() {
    Account acc = makeAccount('Sem Evidencia');
    Exception caught;
    try {
      ALT_CLS_EvidenceQueryService.queryEvidenceForRecord(acc.Id);
    } catch (AXF_CLS_EvidenceQueryException e) {
      caught = e;
    }
    Assert.isNotNull(caught, 'Tipo sem evidencia imutavel e rejeitado.');
  }

  @IsTest
  static void queryEvidence_NullId_Throws() {
    Exception caught;
    try {
      ALT_CLS_EvidenceQueryService.queryEvidenceForRecord(null);
    } catch (AXF_CLS_EvidenceQueryException e) {
      caught = e;
    }
    Assert.isNotNull(caught, 'Id nulo e rejeitado.');
  }

  @IsTest
  static void queryEvidence_AbsentRecord_DeniedWithoutLeak() {
    String prefix = Schema.SObjectType.AXF_OBJ_FxApplicationSnapshot__c.getKeyPrefix();
    Id absentId = (Id) (prefix + '000000000000');

    ALT_CLS_EvidenceQueryService.QueryResultDTO out = ALT_CLS_EvidenceQueryService.queryEvidenceForRecord(
      absentId
    );

    Assert.isFalse(out.found, 'Registro inexistente nao vira resultado.');
    Assert.isTrue(
      out.denied == true,
      'Invisivel/ausente vira negacao sem vazar existencia ou detalhe.'
    );
    Assert.areEqual(0, out.entries.size());
  }
}
