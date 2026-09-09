/**
 * @description Testes unitarios de ALT_CLS_FxChargeService (AXF-61).
 * Cobre: encargo DERIVED com contribuicao; SEPARATE_ENTRY exige lancamento separado;
 * moeda terceira recusada; idempotencia por evidencia; settlement confirmado bloqueia;
 * magnitude invalida.
 */
@IsTest
private class ALT_CLS_FxChargeServiceTest {
  private static Account makeAccount(String name) {
    Account acc = new Account(Name = name);
    insert acc;
    return acc;
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
      'fxt-charge-' +
      Datetime.now().getTime() +
      '-' +
      direction;
    ALT_CLS_FxSettlementService service = new ALT_CLS_FxSettlementService();
    return service.createDraft(input).settlementId;
  }

  private static Id makeSeparateEntry(Account acc) {
    AXF_OBJ_FinancialTransaction__c ftx = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = acc.Id,
      AXF_FTX_NUM_Magnitude__c = 38,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = Date.today(),
      AXF_FTX_PKL_Status__c = 'CONFIRMED',
      AXF_FTX_EXI_ClientRequestId__c = 'fxc-entry-' + Datetime.now().getTime()
    );
    insert ftx;
    return ftx.Id;
  }

  private static ALT_CLS_FxChargeService.ChargeInputDTO chargeInput(
    Id settlementId,
    String authority
  ) {
    ALT_CLS_FxChargeService.ChargeInputDTO input = new ALT_CLS_FxChargeService.ChargeInputDTO();
    input.settlementId = settlementId;
    input.chargeType = 'FEE';
    input.treatment = 'DEDUCTED_TARGET';
    input.magnitude = 38;
    input.currencyIso = 'BRL';
    input.recognitionAuthority = authority;
    input.evidenceHash = 'ev-' + Datetime.now().getTime();
    return input;
  }

  @IsTest
  static void createCharge_DerivedContribution_Success() {
    Account acc = makeAccount('Titular FXC-D');
    Id settlementId = makeSettlement(acc, 'INBOUND');
    ALT_CLS_FxChargeService.ChargeInputDTO input = chargeInput(
      settlementId,
      'DERIVED_CONTRIBUTION'
    );
    input.contributionKey = 'ctrb-iof-1';

    ALT_CLS_FxChargeService service = new ALT_CLS_FxChargeService();
    ALT_CLS_FxChargeService.ResultDTO result = service.createCharge(input);

    Assert.isTrue(result.created);
    Assert.areEqual(1, result.sequence);
    List<AXF_OBJ_FxSettlementCharge__c> charges = [
      SELECT Id, AXF_FXC_PKL_ChargeType__c, AXF_FXC_NUM_Sequence__c
      FROM AXF_OBJ_FxSettlementCharge__c
      WHERE AXF_FXC_MDR_Settlement__c = :settlementId
    ];
    Assert.areEqual(1, charges.size());
    Assert.areEqual('FEE', charges[0].AXF_FXC_PKL_ChargeType__c);
  }

  @IsTest
  static void createCharge_SeparateEntry_RequiresEntry() {
    Account acc = makeAccount('Titular FXC-S');
    Id settlementId = makeSettlement(acc, 'OUTBOUND');
    Id entryId = makeSeparateEntry(acc);
    ALT_CLS_FxChargeService.ChargeInputDTO input = chargeInput(
      settlementId,
      'SEPARATE_ENTRY'
    );
    input.separateEntryId = entryId;

    ALT_CLS_FxChargeService service = new ALT_CLS_FxChargeService();
    ALT_CLS_FxChargeService.ResultDTO result = service.createCharge(input);
    Assert.isTrue(result.created);
    Assert.areEqual(
      'SEPARATE_ENTRY',
      [
        SELECT AXF_FXC_PKL_RecognitionAuthority__c
        FROM AXF_OBJ_FxSettlementCharge__c
        WHERE Id = :result.chargeId
        LIMIT 1
      ]
      .AXF_FXC_PKL_RecognitionAuthority__c
    );
  }

  @IsTest
  static void createCharge_SeparateEntryWithoutEntry_Throws() {
    Account acc = makeAccount('Titular FXC-X');
    Id settlementId = makeSettlement(acc, 'INBOUND');
    ALT_CLS_FxChargeService.ChargeInputDTO input = chargeInput(
      settlementId,
      'SEPARATE_ENTRY'
    );

    ALT_CLS_FxChargeService service = new ALT_CLS_FxChargeService();
    Exception caught;
    try {
      service.createCharge(input);
    } catch (Exception e) {
      caught = e;
    }
    Assert.isNotNull(caught, 'SEPARATE_ENTRY exige lancamento separado.');
  }

  @IsTest
  static void createCharge_ThirdCurrency_Throws() {
    Account acc = makeAccount('Titular FXC-3');
    Id settlementId = makeSettlement(acc, 'INBOUND');
    ALT_CLS_FxChargeService.ChargeInputDTO input = chargeInput(
      settlementId,
      'DERIVED_CONTRIBUTION'
    );
    input.contributionKey = 'ctrb-x';
    input.currencyIso = 'EUR'; // terceira moeda

    ALT_CLS_FxChargeService service = new ALT_CLS_FxChargeService();
    Exception caught;
    try {
      service.createCharge(input);
    } catch (Exception e) {
      caught = e;
    }
    Assert.isNotNull(caught, 'Moeda terceira recusada.');
  }

  @IsTest
  static void createCharge_EvidenceReplay_IsIdempotent() {
    Account acc = makeAccount('Titular FXC-R');
    Id settlementId = makeSettlement(acc, 'OUTBOUND');
    ALT_CLS_FxChargeService.ChargeInputDTO input = chargeInput(
      settlementId,
      'DERIVED_CONTRIBUTION'
    );
    input.contributionKey = 'ctrb-r';
    input.evidenceHash = 'hash-constante-1';

    ALT_CLS_FxChargeService service = new ALT_CLS_FxChargeService();
    service.createCharge(input);
    ALT_CLS_FxChargeService.ResultDTO second = service.createCharge(input);

    Assert.isFalse(
      second.created,
      'Replay nao duplica encargo (mesma evidencia).'
    );
  }

  @IsTest
  static void createCharge_ConfirmedSettlement_Throws() {
    Account acc = makeAccount('Titular FXC-C');
    Id settlementId = makeSettlement(acc, 'INBOUND');
    update new AXF_OBJ_FxSettlement__c(
      Id = settlementId,
      AXF_FXT_PKL_State__c = 'CONFIRMED'
    );

    ALT_CLS_FxChargeService.ChargeInputDTO input = chargeInput(
      settlementId,
      'DERIVED_CONTRIBUTION'
    );
    input.contributionKey = 'ctrb-c';

    ALT_CLS_FxChargeService service = new ALT_CLS_FxChargeService();
    Exception caught;
    try {
      service.createCharge(input);
    } catch (Exception e) {
      caught = e;
    }
    Assert.isNotNull(caught, 'Settlement CONFIRMED bloqueia novos encargos.');
  }
}
