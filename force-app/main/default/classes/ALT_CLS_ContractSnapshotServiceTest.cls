/**
 * @description Testes unitarios de ALT_CLS_ContractSnapshotService (AXF-57).
 * Cobre: snapshot 1:1 imutavel com hash/revision, default versus override, motivo
 * obrigatorio, regeneracao com supersessao (sucessor + SUPERSEDED), bloqueios de
 * cross-account/ausencia de PlanIdentityHash/termo nao ativo, imutabilidade de conteudo
 * e bloqueio de delete. Dados ficticios; testes proporcionais ao delta.
 */
@IsTest
private class ALT_CLS_ContractSnapshotServiceTest {
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
    input.title = 'Contrato de teste AXF-57';
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

  private static List<AXF_OBJ_ContractApplicationSnapshot__c> activeSnapshots(
    Id ftxId
  ) {
    return [
      SELECT
        Id,
        AXF_CAS_EXI_ApplicationIdentityHash__c,
        AXF_CAS_PKL_State__c,
        AXF_CAS_LKP_PredecessorSnapshot__c,
        AXF_CAS_CUR_AppliedAmount__c,
        AXF_CAS_PKL_RemunerationModel__c,
        AXF_CAS_TAL_FieldProvenance__c,
        AXF_CAS_TAL_OverrideReason__c,
        AXF_CAS_LKP_OverriddenByUser__c,
        AXF_CAS_DT_OverriddenAt__c,
        AXF_CAS_NUM_Version__c
      FROM AXF_OBJ_ContractApplicationSnapshot__c
      WHERE
        AXF_CAS_LKP_FinancialTransaction__c = :ftxId
        AND AXF_CAS_PKL_State__c = 'ACTIVE'
      ORDER BY CreatedDate DESC
    ];
  }

  @IsTest
  static void apply_CreatesActiveSnapshot_OneToOneDEFAULTED() {
    Account acc = makeAccount('Titular 1');
    Id contractId = makeContract(acc);
    AXF_OBJ_ContractTermVersion__c term = makeActiveTerm(contractId, 1);
    AXF_OBJ_FinancialTransaction__c ftx = makeContractOccurrence(
      acc,
      'gk-a',
      1,
      true
    );

    ALT_CLS_ContractSnapshotService service = new ALT_CLS_ContractSnapshotService();
    ALT_CLS_ContractSnapshotService.SnapshotInputDTO input = new ALT_CLS_ContractSnapshotService.SnapshotInputDTO();
    input.financialTransactionId = ftx.Id;
    input.termVersionId = term.Id;

    Test.startTest();
    ALT_CLS_ContractSnapshotService.SnapshotResultDTO result = service.applyToOccurrence(
      input
    );
    Test.stopTest();

    Assert.isTrue(result.created, 'Primeira aplicacao cria o snapshot.');
    Assert.areEqual(
      ALT_CLS_ContractSnapshotService.buildIdentityHash(
        ftx.AXF_FTX_EXI_PlanIdentityHash__c,
        term.AXF_CTV_NUM_Revision__c
      ),
      result.identityHash,
      'Identidade = SHA256(frame(PlanIdentityHash, Revision)).'
    );

    List<AXF_OBJ_ContractApplicationSnapshot__c> snaps = activeSnapshots(
      ftx.Id
    );
    Assert.areEqual(1, snaps.size(), 'Snapshot 1:1 ACTIVE.');
    AXF_OBJ_ContractApplicationSnapshot__c cas = snaps[0];
    Assert.areEqual('ACTIVE', cas.AXF_CAS_PKL_State__c);
    Assert.areEqual(1000, cas.AXF_CAS_CUR_AppliedAmount__c);
    Assert.areEqual('FIXED', cas.AXF_CAS_PKL_RemunerationModel__c);

    AXF_OBJ_FinancialTransaction__c linked = [
      SELECT
        AXF_FTX_LKP_Contract__c,
        AXF_FTX_LKP_ContractTermVersion__c,
        AXF_FTX_LKP_ContractApplicationSnapshot__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id = :ftx.Id
      LIMIT 1
    ];
    Assert.areEqual(contractId, linked.AXF_FTX_LKP_Contract__c);
    Assert.areEqual(term.Id, linked.AXF_FTX_LKP_ContractTermVersion__c);
    Assert.areEqual(cas.Id, linked.AXF_FTX_LKP_ContractApplicationSnapshot__c);

    // Reaplicar a mesma (alvo, revisao) e idempotente: nenhum snapshot novo.
    ALT_CLS_ContractSnapshotService.SnapshotResultDTO again = service.applyToOccurrence(
      input
    );
    Assert.isFalse(again.created, 'Reaplicacao idempotente.');
    Assert.areEqual(cas.Id, again.snapshotId);
    Assert.areEqual(1, activeSnapshots(ftx.Id).size());
  }

  @IsTest
  static void apply_NewRevision_SupersedesPreviousSnapshot() {
    Account acc = makeAccount('Titular 2');
    Id contractId = makeContract(acc);
    AXF_OBJ_ContractTermVersion__c termRev1 = makeActiveTerm(contractId, 1);
    AXF_OBJ_ContractTermVersion__c termRev2 = makeActiveTerm(contractId, 2);
    AXF_OBJ_FinancialTransaction__c ftx = makeContractOccurrence(
      acc,
      'gk-b',
      1,
      true
    );

    ALT_CLS_ContractSnapshotService service = new ALT_CLS_ContractSnapshotService();
    ALT_CLS_ContractSnapshotService.SnapshotInputDTO input1 = new ALT_CLS_ContractSnapshotService.SnapshotInputDTO();
    input1.financialTransactionId = ftx.Id;
    input1.termVersionId = termRev1.Id;
    service.applyToOccurrence(input1);

    ALT_CLS_ContractSnapshotService.SnapshotInputDTO input2 = new ALT_CLS_ContractSnapshotService.SnapshotInputDTO();
    input2.financialTransactionId = ftx.Id;
    input2.termVersionId = termRev2.Id;
    ALT_CLS_ContractSnapshotService.SnapshotResultDTO result2 = service.applyToOccurrence(
      input2
    );

    List<AXF_OBJ_ContractApplicationSnapshot__c> all = [
      SELECT Id, AXF_CAS_PKL_State__c
      FROM AXF_OBJ_ContractApplicationSnapshot__c
      WHERE AXF_CAS_LKP_FinancialTransaction__c = :ftx.Id
      ORDER BY CreatedDate ASC
    ];
    Assert.areEqual(
      2,
      all.size(),
      'Dois snapshots: anterior SUPERSEDED + vigente ACTIVE.'
    );
    Assert.areEqual('SUPERSEDED', all[0].AXF_CAS_PKL_State__c);
    Assert.areEqual('ACTIVE', all[1].AXF_CAS_PKL_State__c);
    Assert.areEqual(1, activeSnapshots(ftx.Id).size());

    AXF_OBJ_ContractApplicationSnapshot__c active = activeSnapshots(ftx.Id)[0];
    AXF_OBJ_ContractApplicationSnapshot__c predecessor = [
      SELECT Id
      FROM AXF_OBJ_ContractApplicationSnapshot__c
      WHERE Id = :active.AXF_CAS_LKP_PredecessorSnapshot__c
      LIMIT 1
    ];
    Assert.isNotNull(predecessor, 'Sucessor referencia o predecessor.');
  }

  @IsTest
  static void apply_CrossAccount_Throws() {
    Account accA = makeAccount('Titular A');
    Account accB = makeAccount('Titular B');
    Id contractId = makeContract(accA);
    AXF_OBJ_ContractTermVersion__c term = makeActiveTerm(contractId, 1);
    AXF_OBJ_FinancialTransaction__c ftxB = makeContractOccurrence(
      accB,
      'gk-c',
      1,
      true
    );

    ALT_CLS_ContractSnapshotService service = new ALT_CLS_ContractSnapshotService();
    ALT_CLS_ContractSnapshotService.SnapshotInputDTO input = new ALT_CLS_ContractSnapshotService.SnapshotInputDTO();
    input.financialTransactionId = ftxB.Id;
    input.termVersionId = term.Id;

    Exception caught;
    try {
      service.applyToOccurrence(input);
    } catch (Exception e) {
      caught = e;
    }
    Assert.isNotNull(caught, 'Cross-account deve falhar.');
    Assert.isTrue(
      caught.getMessage().contains('Cross-account'),
      'Mensagem indica violacao de isolamento entre titulares.'
    );
  }

  @IsTest
  static void apply_WithoutPlanIdentityHash_Throws() {
    Account acc = makeAccount('Titular 3');
    Id contractId = makeContract(acc);
    AXF_OBJ_ContractTermVersion__c term = makeActiveTerm(contractId, 1);
    AXF_OBJ_FinancialTransaction__c ftx = makeContractOccurrence(
      acc,
      'gk-d',
      1,
      false
    );

    ALT_CLS_ContractSnapshotService service = new ALT_CLS_ContractSnapshotService();
    ALT_CLS_ContractSnapshotService.SnapshotInputDTO input = new ALT_CLS_ContractSnapshotService.SnapshotInputDTO();
    input.financialTransactionId = ftx.Id;
    input.termVersionId = term.Id;

    Exception caught;
    try {
      service.applyToOccurrence(input);
    } catch (Exception e) {
      caught = e;
    }
    Assert.isNotNull(
      caught,
      'Ocorrencia sem PlanIdentityHash nao pode receber snapshot.'
    );
  }

  @IsTest
  static void apply_NonActiveTerm_Throws() {
    Account acc = makeAccount('Titular 4');
    Id contractId = makeContract(acc);
    AXF_OBJ_ContractTermVersion__c term = new AXF_OBJ_ContractTermVersion__c(
      AXF_CTV_LKP_Contract__c = contractId,
      AXF_CTV_NUM_Revision__c = 1,
      AXF_CTV_PKL_Status__c = 'DRAFT',
      AXF_CTV_PKL_RemunerationModel__c = 'FIXED',
      AXF_CTV_CUR_ContractedAmount__c = 1000,
      AXF_CTV_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CTV_DAT_EffectiveFrom__c = Date.today().addMonths(-1),
      AXF_CTV_NUM_Version__c = 1
    );
    insert term;

    AXF_OBJ_FinancialTransaction__c ftx = makeContractOccurrence(
      acc,
      'gk-e',
      1,
      true
    );

    ALT_CLS_ContractSnapshotService service = new ALT_CLS_ContractSnapshotService();
    ALT_CLS_ContractSnapshotService.SnapshotInputDTO input = new ALT_CLS_ContractSnapshotService.SnapshotInputDTO();
    input.financialTransactionId = ftx.Id;
    input.termVersionId = term.Id;

    Exception caught;
    try {
      service.applyToOccurrence(input);
    } catch (Exception e) {
      caught = e;
    }
    Assert.isNotNull(caught, 'Somente TermVersion ACTIVE pode ser aplicada.');
  }

  @IsTest
  static void override_PreservesDefault_AndFlagsOverridden() {
    Account acc = makeAccount('Titular 5');
    Id contractId = makeContract(acc);
    AXF_OBJ_ContractTermVersion__c term = makeActiveTerm(contractId, 1);
    AXF_OBJ_FinancialTransaction__c ftx = makeContractOccurrence(
      acc,
      'gk-f',
      1,
      true
    );

    ALT_CLS_ContractSnapshotService service = new ALT_CLS_ContractSnapshotService();
    ALT_CLS_ContractSnapshotService.SnapshotInputDTO input = new ALT_CLS_ContractSnapshotService.SnapshotInputDTO();
    input.financialTransactionId = ftx.Id;
    input.termVersionId = term.Id;
    service.applyToOccurrence(input);

    ALT_CLS_ContractSnapshotService.OverrideInputDTO ovr = new ALT_CLS_ContractSnapshotService.OverrideInputDTO();
    ovr.financialTransactionId = ftx.Id;
    ovr.fieldApiName = 'AXF_FTX_NUM_Magnitude__c';
    ovr.newValue = 1200;
    ovr.reason = 'Reajuste negociado com a contraparte.';

    service.recordOverride(ovr);

    AXF_OBJ_FinancialTransaction__c updated = [
      SELECT AXF_FTX_NUM_Magnitude__c, AXF_FTX_DAT_DueDate__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id = :ftx.Id
      LIMIT 1
    ];
    Assert.areEqual(
      1200,
      updated.AXF_FTX_NUM_Magnitude__c,
      'Valor efetivo overridden.'
    );

    AXF_OBJ_ContractApplicationSnapshot__c cas = activeSnapshots(ftx.Id)[0];
    Assert.areEqual(
      1000,
      cas.AXF_CAS_CUR_AppliedAmount__c,
      'Default preservado no CAS imutavel.'
    );

    Map<String, String> provenance = ALT_CLS_ContractSnapshotService.parseProvenance(
      cas.AXF_CAS_TAL_FieldProvenance__c
    );
    Assert.areEqual('OVERRIDDEN', provenance.get('AXF_FTX_NUM_Magnitude__c'));
    Assert.areEqual('DEFAULTED', provenance.get('AXF_FTX_DAT_DueDate__c'));
    Assert.areEqual(
      'Reajuste negociado com a contraparte.',
      cas.AXF_CAS_TAL_OverrideReason__c
    );
    Assert.areEqual(UserInfo.getUserId(), cas.AXF_CAS_LKP_OverriddenByUser__c);
    Assert.isNotNull(
      cas.AXF_CAS_DT_OverriddenAt__c,
      'Instante do override gravado.'
    );
    Assert.areEqual(
      1,
      cas.AXF_CAS_NUM_Version__c,
      'Versao avanca no override.'
    );
  }

  @IsTest
  static void override_WithoutReason_Throws() {
    Account acc = makeAccount('Titular 6');
    Id contractId = makeContract(acc);
    AXF_OBJ_ContractTermVersion__c term = makeActiveTerm(contractId, 1);
    AXF_OBJ_FinancialTransaction__c ftx = makeContractOccurrence(
      acc,
      'gk-g',
      1,
      true
    );

    ALT_CLS_ContractSnapshotService service = new ALT_CLS_ContractSnapshotService();
    ALT_CLS_ContractSnapshotService.SnapshotInputDTO input = new ALT_CLS_ContractSnapshotService.SnapshotInputDTO();
    input.financialTransactionId = ftx.Id;
    input.termVersionId = term.Id;
    service.applyToOccurrence(input);

    ALT_CLS_ContractSnapshotService.OverrideInputDTO ovr = new ALT_CLS_ContractSnapshotService.OverrideInputDTO();
    ovr.financialTransactionId = ftx.Id;
    ovr.fieldApiName = 'AXF_FTX_NUM_Magnitude__c';
    ovr.newValue = 1200;

    Exception caught;
    try {
      service.recordOverride(ovr);
    } catch (Exception e) {
      caught = e;
    }
    Assert.isNotNull(caught, 'Override sem motivo deve falhar (AC 2).');
  }

  @IsTest
  static void override_UnknownField_Throws() {
    Account acc = makeAccount('Titular 7');
    Id contractId = makeContract(acc);
    AXF_OBJ_ContractTermVersion__c term = makeActiveTerm(contractId, 1);
    AXF_OBJ_FinancialTransaction__c ftx = makeContractOccurrence(
      acc,
      'gk-h',
      1,
      true
    );

    ALT_CLS_ContractSnapshotService service = new ALT_CLS_ContractSnapshotService();
    ALT_CLS_ContractSnapshotService.SnapshotInputDTO input = new ALT_CLS_ContractSnapshotService.SnapshotInputDTO();
    input.financialTransactionId = ftx.Id;
    input.termVersionId = term.Id;
    service.applyToOccurrence(input);

    ALT_CLS_ContractSnapshotService.OverrideInputDTO ovr = new ALT_CLS_ContractSnapshotService.OverrideInputDTO();
    ovr.financialTransactionId = ftx.Id;
    ovr.fieldApiName = 'AXF_FTX_TXT_ScheduleGroupKey__c';
    ovr.newValue = 'x';
    ovr.reason = 'Motivo qualquer.';

    Exception caught;
    try {
      service.recordOverride(ovr);
    } catch (Exception e) {
      caught = e;
    }
    Assert.isNotNull(caught, 'Campo fora da whitelist nao e overridable.');
  }

  @IsTest
  static void override_ManualTransaction_Throws() {
    Account acc = makeAccount('Titular 8');
    AXF_OBJ_FinancialTransaction__c manual = makeContractOccurrence(
      acc,
      'gk-manual',
      1,
      false
    );

    ALT_CLS_ContractSnapshotService service = new ALT_CLS_ContractSnapshotService();
    ALT_CLS_ContractSnapshotService.OverrideInputDTO ovr = new ALT_CLS_ContractSnapshotService.OverrideInputDTO();
    ovr.financialTransactionId = manual.Id;
    ovr.fieldApiName = 'AXF_FTX_NUM_Magnitude__c';
    ovr.newValue = 500;
    ovr.reason = 'Motivo qualquer.';

    Exception caught;
    try {
      service.recordOverride(ovr);
    } catch (Exception e) {
      caught = e;
    }
    Assert.isNotNull(
      caught,
      'Override so existe em ocorrencia contratual com snapshot.'
    );
  }

  @IsTest
  static void immutability_ContentUpdateAndDelete_AreBlocked() {
    Account acc = makeAccount('Titular 9');
    Id contractId = makeContract(acc);
    AXF_OBJ_ContractTermVersion__c term = makeActiveTerm(contractId, 1);
    AXF_OBJ_FinancialTransaction__c ftx = makeContractOccurrence(
      acc,
      'gk-i',
      1,
      true
    );

    ALT_CLS_ContractSnapshotService service = new ALT_CLS_ContractSnapshotService();
    ALT_CLS_ContractSnapshotService.SnapshotInputDTO input = new ALT_CLS_ContractSnapshotService.SnapshotInputDTO();
    input.financialTransactionId = ftx.Id;
    input.termVersionId = term.Id;
    service.applyToOccurrence(input);

    AXF_OBJ_ContractApplicationSnapshot__c cas = activeSnapshots(ftx.Id)[0];

    // Update de conteudo congelado deve falhar na trigger.
    AXF_OBJ_ContractApplicationSnapshot__c tampered = new AXF_OBJ_ContractApplicationSnapshot__c(
      Id = cas.Id,
      AXF_CAS_CUR_AppliedAmount__c = 9999
    );
    Exception caughtUpdate;
    try {
      update tampered;
    } catch (Exception e) {
      caughtUpdate = e;
    }
    Assert.isNotNull(
      caughtUpdate,
      'Conteudo congelado nao pode ser alterado (G7-2).'
    );

    // Delete deve falhar (nenhum PSG concede Delete).
    Exception caughtDelete;
    try {
      delete cas;
    } catch (Exception e) {
      caughtDelete = e;
    }
    Assert.isNotNull(caughtDelete, 'Snapshot imutavel nao pode ser excluido.');
  }
}
