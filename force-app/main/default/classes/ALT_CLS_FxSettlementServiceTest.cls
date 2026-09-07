/**
 * @description Testes unitarios de ALT_CLS_FxSettlementService (AXF-59).
 * Cobre: rascunho completo (DRAFT), dados ausentes -> PENDING_DETAILS sem presumir
 * taxa/encargo, idempotencia por SettlementKey, validacao de direcao/magnitude e
 * bloqueio de delete (trigger).
 */
@IsTest
private class ALT_CLS_FxSettlementServiceTest {
  private static Account makeAccount(String name) {
    Account acc = new Account(Name = name);
    insert acc;
    return acc;
  }

  private static ALT_CLS_FxSettlementService.DraftInputDTO baseInput(Id accountId) {
    ALT_CLS_FxSettlementService.DraftInputDTO input = new ALT_CLS_FxSettlementService.DraftInputDTO();
    input.accountId = accountId;
    input.direction = 'INBOUND';
    input.sourceCurrency = 'USD';
    input.targetCurrency = 'BRL';
    input.operationKey = 'op-axf59-' + Datetime.now().getTime();
    input.timeZone = 'America/Sao_Paulo';
    return input;
  }

  @IsTest
  static void createDraft_Complete_StateDraft() {
    Account acc = makeAccount('Titular FXT');
    ALT_CLS_FxSettlementService.DraftInputDTO input = baseInput(acc.Id);
    input.expectedSource = 1000;
    input.deliveredSource = 1000;
    input.convertedSource = 5050;
    input.effectiveRate = 5.05;
    input.grossTargetAmount = 5050;
    input.netBankMovement = 5050;
    input.tradeDate = Date.today();
    input.valueDate = Date.today();
    input.postingDate = Date.today();

    ALT_CLS_FxSettlementService service = new ALT_CLS_FxSettlementService();
    ALT_CLS_FxSettlementService.ResultDTO result = service.createDraft(input);

    Assert.isTrue(result.created);
    Assert.areEqual('DRAFT', result.state);

    AXF_OBJ_FxSettlement__c saved = [
      SELECT
        AXF_FXT_PKL_Direction__c,
        AXF_FXT_TXT_SourceCurrency__c,
        AXF_FXT_TXT_CurrencyIsoCode__c,
        AXF_FXT_NUM_EffectiveRate__c,
        AXF_FXT_TXT_Provider__c,
        AXF_FXT_PKL_Kind__c,
        AXF_FXT_EXI_SettlementKey__c
      FROM AXF_OBJ_FxSettlement__c
      WHERE Id = :result.settlementId
      LIMIT 1
    ];
    Assert.areEqual('INBOUND', saved.AXF_FXT_PKL_Direction__c);
    Assert.areEqual('USD', saved.AXF_FXT_TXT_SourceCurrency__c);
    Assert.areEqual('BRL', saved.AXF_FXT_TXT_CurrencyIsoCode__c);
    Assert.areEqual(5.05, saved.AXF_FXT_NUM_EffectiveRate__c);
    Assert.areEqual('MANUAL', saved.AXF_FXT_TXT_Provider__c);
    Assert.areEqual('PRIMARY', saved.AXF_FXT_PKL_Kind__c);
    Assert.isFalse(String.isBlank(saved.AXF_FXT_EXI_SettlementKey__c));
  }

  @IsTest
  static void createDraft_Incomplete_PendingDetails_NoInvention() {
    Account acc = makeAccount('Titular PEND');
    ALT_CLS_FxSettlementService.DraftInputDTO input = baseInput(acc.Id);
    input.expectedSource = 1000;
    input.deliveredSource = 1000; // caixa observado conhecido, sem taxa/valor alvo

    ALT_CLS_FxSettlementService service = new ALT_CLS_FxSettlementService();
    ALT_CLS_FxSettlementService.ResultDTO result = service.createDraft(input);

    Assert.areEqual('PENDING_DETAILS', result.state, 'Dados ausentes -> PENDING_DETAILS.');

    AXF_OBJ_FxSettlement__c saved = [
      SELECT
        AXF_FXT_NUM_EffectiveRate__c,
        AXF_FXT_NUM_ConvertedSource__c,
        AXF_FXT_CUR_GrossTargetAmount__c,
        AXF_FXT_NUM_DeliveredSource__c
      FROM AXF_OBJ_FxSettlement__c
      WHERE Id = :result.settlementId
      LIMIT 1
    ];
    Assert.areEqual(null, saved.AXF_FXT_NUM_EffectiveRate__c, 'Nao presume taxa.');
    Assert.areEqual(null, saved.AXF_FXT_NUM_ConvertedSource__c, 'Nao presume valor convertido.');
    Assert.areEqual(null, saved.AXF_FXT_CUR_GrossTargetAmount__c, 'Nao presume bruto alvo.');
    Assert.areEqual(1000, saved.AXF_FXT_NUM_DeliveredSource__c, 'Preserva caixa observado conhecido.');
  }

  @IsTest
  static void createDraft_DuplicateOperationKey_IsIdempotent() {
    Account acc = makeAccount('Titular DUP');
    ALT_CLS_FxSettlementService.DraftInputDTO input = baseInput(acc.Id);
    input.expectedSource = 1000;
    input.deliveredSource = 1000;
    input.effectiveRate = 5.0;
    input.grossTargetAmount = 5000;
    input.valueDate = Date.today();

    ALT_CLS_FxSettlementService service = new ALT_CLS_FxSettlementService();
    service.createDraft(input);
    ALT_CLS_FxSettlementService.ResultDTO second = service.createDraft(input);

    Assert.isFalse(second.created, 'Replay nao duplica (SettlementKey G6).');
    Integer count = [
      SELECT COUNT()
      FROM AXF_OBJ_FxSettlement__c
      WHERE AXF_FXT_TXT_OperationKey__c = :input.operationKey
    ];
    Assert.areEqual(1, count);
  }

  @IsTest
  static void createDraft_InvalidDirection_Throws() {
    Account acc = makeAccount('Titular DIR');
    ALT_CLS_FxSettlementService.DraftInputDTO input = baseInput(acc.Id);
    input.direction = 'SIDEWAYS';

    ALT_CLS_FxSettlementService service = new ALT_CLS_FxSettlementService();
    Exception caught;
    try {
      service.createDraft(input);
    } catch (Exception e) {
      caught = e;
    }
    Assert.isNotNull(caught, 'Direcao invalida rejeitada.');
  }

  @IsTest
  static void createDraft_NegativeMagnitude_Throws() {
    Account acc = makeAccount('Titular NEG');
    ALT_CLS_FxSettlementService.DraftInputDTO input = baseInput(acc.Id);
    input.expectedSource = -10;

    ALT_CLS_FxSettlementService service = new ALT_CLS_FxSettlementService();
    Exception caught;
    try {
      service.createDraft(input);
    } catch (Exception e) {
      caught = e;
    }
    Assert.isNotNull(caught, 'Magnitude negativa rejeitada (Money contract).');
  }

  @IsTest
  static void settlement_NoDelete_IsEnforced() {
    Account acc = makeAccount('Titular DEL');
    ALT_CLS_FxSettlementService.DraftInputDTO input = baseInput(acc.Id);
    input.expectedSource = 1000;
    input.deliveredSource = 1000;
    input.effectiveRate = 5.0;
    input.grossTargetAmount = 5000;
    input.valueDate = Date.today();

    ALT_CLS_FxSettlementService service = new ALT_CLS_FxSettlementService();
    ALT_CLS_FxSettlementService.ResultDTO result = service.createDraft(input);

    Exception caught;
    try {
      delete new AXF_OBJ_FxSettlement__c(Id = result.settlementId);
    } catch (Exception e) {
      caught = e;
    }
    Assert.isNotNull(caught, 'FxSettlement nao pode ser excluida.');
  }
}
