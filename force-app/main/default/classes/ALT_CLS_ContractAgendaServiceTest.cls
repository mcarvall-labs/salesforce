/**
 * @description Testes unitarios de ALT_CLS_ContractAgendaService (AXF-55).
 * Cobre: token unico Contract+ACTIVE (concorrencia), previa delta sem publicacao,
 * publicacao cria ocorrencias FTX PLANNED + CAS DEFAULTED, replay idempotente,
 * BLOCKED para confirmado/override e SUPERSEDED para draft intocado, retomada apos
 * FAILED com checkpoint, extensao de horizonte (preserve+add), e imutabilidade/delete do CSR.
 */
@IsTest
private class ALT_CLS_ContractAgendaServiceTest {
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

  private static Id makeContract(Account acc) {
    AXF_OBJ_Counterparty__c cpty = new AXF_OBJ_Counterparty__c(
      Name = 'Fornecedor ' + acc.Name,
      AXF_CPTY_TXT_DisplayName__c = 'Fornecedor ' + acc.Name,
      AXF_CPTY_TXT_LegalName__c = 'Fornecedor ' + acc.Name + ' LTDA',
      AXF_CPTY_TXT_Country__c = 'BR',
      AXF_CPTY_PKL_Kind__c = 'ORGANIZATION',
      AXF_CPTY_PKL_Status__c = 'ACTIVE',
      AXF_CPTY_EXI_CounterpartyKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'CPTY', 'Fornecedor ' + acc.Name + ' LTDA', 'BR' }
      ),
      AXF_CPTY_NUM_Version__c = 1
    );
    insert cpty;

    AXF_OBJ_CounterpartyEntityRelationship__c rel = new AXF_OBJ_CounterpartyEntityRelationship__c(
      AXF_CER_LKP_Counterparty__c = cpty.Id,
      AXF_CER_LKP_Account__c = acc.Id,
      AXF_CER_PKL_Role__c = 'SUPPLIER',
      AXF_CER_PKL_Status__c = 'ACTIVE',
      AXF_CER_TXT_EntitySpecificDisplay__c = 'Fornecedor Principal',
      AXF_CER_EXI_RelationshipKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'CER', cpty.Id, acc.Id, 'SUPPLIER' }
      ),
      AXF_CER_NUM_Version__c = 1
    );
    insert rel;

    ALT_CLS_ContractService.ContractInputDTO input = new ALT_CLS_ContractService.ContractInputDTO();
    input.accountId = acc.Id;
    input.relationshipId = rel.Id;
    input.contractCode = 'CTR-AXF55-' + Datetime.now().getTime();
    input.title = 'Contrato de teste AXF-55';
    input.contractType = 'EXPENSE';
    input.currencyIsoCode = 'BRL';
    input.startDate = Date.today().addMonths(-1);
    input.endDate = Date.today().addYears(1);

    ALT_CLS_ContractService service = new ALT_CLS_ContractService();
    ALT_CLS_ContractService.OperationResultDTO res = service.createDraftContract(
      input
    );
    Assert.isTrue(res.success, 'Contrato de teste criado.');
    return res.contractId;
  }

  private static Date monthStart(Integer offsetMonths) {
    Date today = Date.today();
    Date base = Date.newInstance(today.year(), today.month(), 1);
    return base.addMonths(offsetMonths);
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
      AXF_CTV_CUR_ContractedAmount__c = 1200,
      AXF_CTV_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CTV_DAT_EffectiveFrom__c = monthStart(-1),
      AXF_CTV_DAT_EffectiveTo__c = monthStart(-1).addMonths(11),
      AXF_CTV_NUM_Installments__c = 12,
      AXF_CTV_TXT_CalendarPolicy__c = 'CALENDAR_DAYS',
      AXF_CTV_TXT_TimeZone__c = 'America/Sao_Paulo',
      AXF_CTV_NUM_Version__c = 1
    );
    insert term;
    return term;
  }

  private static Integer countOccurrences(Id contractId) {
    return [
      SELECT COUNT()
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Contract__c = :contractId
    ];
  }

  private static ALT_CLS_ContractAgendaService.RunInputDTO runInput(
    Id contractId,
    Id termId,
    Date horizonStart,
    Date horizonEnd
  ) {
    ALT_CLS_ContractAgendaService.RunInputDTO input = new ALT_CLS_ContractAgendaService.RunInputDTO();
    input.contractId = contractId;
    input.termVersionId = termId;
    input.horizonFrom = horizonStart;
    input.horizonThrough = horizonEnd;
    return input;
  }

  @IsTest
  static void createRun_ConcurrentRuns_ReturnSingleActive() {
    Account acc = makeAccount('Titular CX');
    Id contractId = makeContract(acc);
    AXF_OBJ_ContractTermVersion__c term = makeActiveTerm(contractId, 1);

    ALT_CLS_ContractAgendaService service = new ALT_CLS_ContractAgendaService();
    ALT_CLS_ContractAgendaService.RunResultDTO first = service.createRun(
      runInput(contractId, term.Id, monthStart(0), monthStart(2))
    );
    ALT_CLS_ContractAgendaService.RunResultDTO second = service.createRun(
      runInput(contractId, term.Id, monthStart(0), monthStart(3))
    );

    Assert.isTrue(first.created, 'Primeiro run criado.');
    Assert.isFalse(
      second.created,
      'Run concorrente nao duplica: acompanha o existente (AC 1).'
    );
    Assert.areEqual(first.runId, second.runId);

    Integer activeRuns = [
      SELECT COUNT()
      FROM AXF_OBJ_ContractScheduleRun__c
      WHERE AXF_CSR_EXI_ActiveScopeToken__c != NULL
    ];
    Assert.areEqual(1, activeRuns, 'Apenas um token Contract+ACTIVE ativo.');
  }

  @IsTest
  static void computePreview_PublishesNothing() {
    Account acc = makeAccount('Titular PV');
    Id contractId = makeContract(acc);
    AXF_OBJ_ContractTermVersion__c term = makeActiveTerm(contractId, 1);

    ALT_CLS_ContractAgendaService service = new ALT_CLS_ContractAgendaService();
    ALT_CLS_ContractAgendaService.RunResultDTO run = service.createRun(
      runInput(contractId, term.Id, monthStart(0), monthStart(2))
    );

    ALT_CLS_ContractAgendaService.RunResultDTO preview = service.computePreview(
      run.runId
    );

    Assert.areEqual(
      0,
      countOccurrences(contractId),
      'Nada publicado antes da confirmacao (AC 2).'
    );
    Assert.areEqual(
      3,
      preview.added,
      '3 ocorrencias adicionadas previstas no horizonte.'
    );
    Assert.areEqual('PREVIEW', preview.state);

    AXF_OBJ_ContractScheduleRun__c persisted = [
      SELECT AXF_CSR_TAL_PreviewJson__c, AXF_CSR_PKL_State__c
      FROM AXF_OBJ_ContractScheduleRun__c
      WHERE Id = :run.runId
      LIMIT 1
    ];
    Assert.isFalse(
      String.isBlank(persisted.AXF_CSR_TAL_PreviewJson__c),
      'Preview persiste JSON.'
    );
  }

  @IsTest
  static void publish_CreatesOccurrencesWithSnapshots() {
    Account acc = makeAccount('Titular PB');
    Id contractId = makeContract(acc);
    AXF_OBJ_ContractTermVersion__c term = makeActiveTerm(contractId, 1);

    ALT_CLS_ContractAgendaService service = new ALT_CLS_ContractAgendaService();
    ALT_CLS_ContractAgendaService.RunResultDTO run = service.createRun(
      runInput(contractId, term.Id, monthStart(0), monthStart(2))
    );
    service.computePreview(run.runId);
    ALT_CLS_ContractAgendaService.RunResultDTO done = service.publish(
      run.runId
    );

    Assert.areEqual(3, countOccurrences(contractId));
    Assert.areEqual('COMPLETE', done.state);
    Assert.areEqual(3, done.added);

    Integer cas = [
      SELECT COUNT()
      FROM AXF_OBJ_ContractApplicationSnapshot__c
      WHERE
        AXF_CAS_LKP_FinancialTransaction__r.AXF_FTX_LKP_Contract__c = :contractId
    ];
    Assert.areEqual(3, cas, 'Cada ocorrencia recebe CAS imutavel (AXF-57).');

    AXF_OBJ_ContractScheduleRun__c finalState = [
      SELECT
        AXF_CSR_TXT_Watermark__c,
        AXF_CSR_DAT_CompleteThrough__c,
        AXF_CSR_EXI_ActiveScopeToken__c
      FROM AXF_OBJ_ContractScheduleRun__c
      WHERE Id = :run.runId
      LIMIT 1
    ];
    Assert.isNotNull(
      finalState.AXF_CSR_DAT_CompleteThrough__c,
      'Complete-through gravado.'
    );
    Assert.areEqual(
      null,
      finalState.AXF_CSR_EXI_ActiveScopeToken__c,
      'Token liberado ao concluir.'
    );
  }

  @IsTest
  static void replay_AfterComplete_IsIdempotent() {
    Account acc = makeAccount('Titular RP');
    Id contractId = makeContract(acc);
    AXF_OBJ_ContractTermVersion__c term = makeActiveTerm(contractId, 1);

    ALT_CLS_ContractAgendaService service = new ALT_CLS_ContractAgendaService();
    ALT_CLS_ContractAgendaService.RunResultDTO first = service.createRun(
      runInput(contractId, term.Id, monthStart(0), monthStart(2))
    );
    service.computePreview(first.runId);
    service.publish(first.runId);

    ALT_CLS_ContractAgendaService.RunResultDTO replay = service.createRun(
      runInput(contractId, term.Id, monthStart(0), monthStart(2))
    );

    Assert.areEqual(
      first.runId,
      replay.runId,
      'Replay retorna o run original (G6).'
    );
    Assert.areEqual('COMPLETE', replay.state);
    Assert.areEqual(
      3,
      countOccurrences(contractId),
      'Replay nao duplica ocorrencias.'
    );
  }

  @IsTest
  static void publish_BlocksProtected_AndSupersedesIntocado() {
    Account acc = makeAccount('Titular BL');
    Id contractId = makeContract(acc);
    AXF_OBJ_ContractTermVersion__c term = makeActiveTerm(contractId, 1);
    AXF_OBJ_Contract__c contract = [
      SELECT Id, AXF_CTR_EXI_ContractKey__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :contractId
      LIMIT 1
    ];

    // Semeadura: ocorrencias PLANNED + CAS como um run anterior teria publicado (seq 2,3,4 caem
    // no horizonte [monthStart(0) .. monthStart(2)] dado effectiveFrom = monthStart(-1)).
    List<AXF_OBJ_FinancialTransaction__c> seeded = new List<AXF_OBJ_FinancialTransaction__c>();
    for (Integer seq = 2; seq <= 4; seq++) {
      Date due = term.AXF_CTV_DAT_EffectiveFrom__c.addMonths(seq - 1);
      seeded.add(
        seedOccurrence(
          acc.Id,
          contract.Id,
          contract.AXF_CTR_EXI_ContractKey__c,
          term.Id,
          seq,
          due,
          100
        )
      );
    }

    // 1) Confirmada (protegida), 2) overridden (protegida), 3) draft intocado editado (supersede)
    AXF_OBJ_FinancialTransaction__c confirmed = seeded[0];
    confirmed.AXF_FTX_PKL_Status__c = 'CONFIRMED';
    update confirmed;

    AXF_OBJ_FinancialTransaction__c overridden = seeded[1];
    ALT_CLS_ContractSnapshotService snap = new ALT_CLS_ContractSnapshotService();
    ALT_CLS_ContractSnapshotService.OverrideInputDTO ovr = new ALT_CLS_ContractSnapshotService.OverrideInputDTO();
    ovr.financialTransactionId = overridden.Id;
    ovr.fieldApiName = 'AXF_FTX_NUM_Magnitude__c';
    ovr.newValue = 111;
    ovr.reason = 'Override de teste (protegido).';
    snap.recordOverride(ovr);

    AXF_OBJ_FinancialTransaction__c touched = seeded[2];
    touched.AXF_FTX_NUM_Magnitude__c = 42;
    update touched;

    // Novo run PREVIEW para o mesmo horizonte: protegidos nao podem mudar.
    ALT_CLS_ContractAgendaService service = new ALT_CLS_ContractAgendaService();
    ALT_CLS_ContractAgendaService.RunResultDTO run = service.createRun(
      runInput(contractId, term.Id, monthStart(0), monthStart(2))
    );
    ALT_CLS_ContractAgendaService.RunResultDTO preview = service.computePreview(
      run.runId
    );
    Assert.areEqual(
      2,
      preview.blocked,
      'Confirmado + overridden sao bloqueados (AC 3).'
    );
    Assert.areEqual(
      1,
      preview.superseded,
      'Draft gerado intocado e superseded.'
    );

    // Publicar nao toca os protegidos e restaura o intocado para o valor canonico.
    service.publish(run.runId);

    Map<Id, AXF_OBJ_FinancialTransaction__c> after = new Map<Id, AXF_OBJ_FinancialTransaction__c>(
      [
        SELECT Id, AXF_FTX_NUM_Magnitude__c, AXF_FTX_PKL_Status__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id IN :seeded
      ]
    );
    Assert.areEqual(100, after.get(confirmed.Id).AXF_FTX_NUM_Magnitude__c);
    Assert.areEqual('CONFIRMED', after.get(confirmed.Id).AXF_FTX_PKL_Status__c);
    Assert.areEqual(
      111,
      after.get(overridden.Id).AXF_FTX_NUM_Magnitude__c,
      'Override preservado.'
    );
    Assert.areEqual(
      100,
      after.get(touched.Id).AXF_FTX_NUM_Magnitude__c,
      'Draft intocado restaurado (superseded).'
    );
  }

  /** Semeia uma ocorrencia PLANNED gerada por contrato (mesma forma que o motor publica) + CAS. */
  private static AXF_OBJ_FinancialTransaction__c seedOccurrence(
    Id accountId,
    Id contractId,
    String contractKey,
    Id termId,
    Integer sequence,
    Date dueDate,
    Decimal amount
  ) {
    String occurrenceKey = AXF_CLS_IdentityFraming.key(
      new List<Object>{ 'ftx-agenda-v1', contractKey, '1', sequence }
    );
    AXF_OBJ_FinancialTransaction__c ftx = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = accountId,
      AXF_FTX_LKP_Contract__c = contractId,
      AXF_FTX_LKP_ContractTermVersion__c = termId,
      AXF_FTX_NUM_Magnitude__c = amount,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = dueDate,
      AXF_FTX_DAT_DueDate__c = dueDate,
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_TXT_ScheduleGroupKey__c = 'agenda-seed-' + sequence,
      AXF_FTX_EXI_PlanIdentityHash__c = occurrenceKey,
      AXF_FTX_EXI_ClientRequestId__c = occurrenceKey.substring(0, 36)
    );
    insert ftx;

    ALT_CLS_ContractSnapshotService snap = new ALT_CLS_ContractSnapshotService();
    ALT_CLS_ContractSnapshotService.SnapshotInputDTO input = new ALT_CLS_ContractSnapshotService.SnapshotInputDTO();
    input.financialTransactionId = ftx.Id;
    input.termVersionId = termId;
    snap.applyToOccurrence(input);
    return ftx;
  }

  @IsTest
  static void publish_ResumeAfterFailed_AppliesIdempotently() {
    Account acc = makeAccount('Titular RS');
    Id contractId = makeContract(acc);
    AXF_OBJ_ContractTermVersion__c term = makeActiveTerm(contractId, 1);

    ALT_CLS_ContractAgendaService service = new ALT_CLS_ContractAgendaService();
    ALT_CLS_ContractAgendaService.RunResultDTO run = service.createRun(
      runInput(contractId, term.Id, monthStart(0), monthStart(1))
    );
    service.computePreview(run.runId);

    // Simula falha entre etapas (estado FAILED retomavel, token mantido).
    AXF_OBJ_ContractScheduleRun__c failed = new AXF_OBJ_ContractScheduleRun__c(
      Id = run.runId,
      AXF_CSR_PKL_State__c = 'FAILED'
    );
    update failed;

    ALT_CLS_ContractAgendaService.RunResultDTO resumed = service.publish(
      run.runId
    );

    Assert.areEqual('COMPLETE', resumed.state);
    Assert.areEqual(2, countOccurrences(contractId));
  }

  @IsTest
  static void publish_ExtendsHorizon_PreservesAndAdds() {
    Account acc = makeAccount('Titular HZ');
    Id contractId = makeContract(acc);
    AXF_OBJ_ContractTermVersion__c term = makeActiveTerm(contractId, 1);

    ALT_CLS_ContractAgendaService service = new ALT_CLS_ContractAgendaService();
    ALT_CLS_ContractAgendaService.RunResultDTO first = service.createRun(
      runInput(contractId, term.Id, monthStart(0), monthStart(2))
    );
    service.computePreview(first.runId);
    service.publish(first.runId);
    Assert.areEqual(3, countOccurrences(contractId));

    ALT_CLS_ContractAgendaService.RunResultDTO next = service.createRun(
      runInput(contractId, term.Id, monthStart(1), monthStart(4))
    );
    Assert.isTrue(next.created, 'Novo run apos conclusao do anterior.');
    ALT_CLS_ContractAgendaService.RunResultDTO preview = service.computePreview(
      next.runId
    );
    Assert.areEqual(
      2,
      preview.preserved,
      'Janela sobreposta preserva ocorrencias existentes.'
    );
    Assert.areEqual(
      2,
      preview.added,
      'Nova janela adiciona ocorrencias seguintes.'
    );
    service.publish(next.runId);
    Assert.areEqual(
      5,
      countOccurrences(contractId),
      'Sem duplicacao entre janelas.'
    );
  }

  @IsTest
  static void csr_ImmutabilityAndNoDelete_AreEnforced() {
    Account acc = makeAccount('Titular IM');
    Id contractId = makeContract(acc);
    AXF_OBJ_ContractTermVersion__c term = makeActiveTerm(contractId, 1);

    ALT_CLS_ContractAgendaService service = new ALT_CLS_ContractAgendaService();
    ALT_CLS_ContractAgendaService.RunResultDTO run = service.createRun(
      runInput(contractId, term.Id, monthStart(0), monthStart(1))
    );

    Exception caughtDelete;
    try {
      delete new AXF_OBJ_ContractScheduleRun__c(Id = run.runId);
    } catch (Exception e) {
      caughtDelete = e;
    }
    Assert.isNotNull(caughtDelete, 'CSR nao pode ser excluido.');

    Exception caughtEdit;
    try {
      update new AXF_OBJ_ContractScheduleRun__c(
        Id = run.runId,
        AXF_CSR_LKP_TermVersion__c = makeActiveTerm(contractId, 2).Id
      );
    } catch (Exception e) {
      caughtEdit = e;
    }
    Assert.isNotNull(caughtEdit, 'Vinculos imutaveis apos criacao.');
  }
}
