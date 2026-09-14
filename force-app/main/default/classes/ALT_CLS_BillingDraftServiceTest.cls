/**
 * @description AXF-65: composicao de rascunho de cobranca compativel — caminho feliz,
 * incompatibilidades explicadas sem linha parcial, conservacao do total, alocacao de trabalho
 * dentro do saldo, idempotencia/CONFLICT, guards de trigger e acesso negado sem vazamento.
 */
@IsTest
private class ALT_CLS_BillingDraftServiceTest {
  private class Fixture {
    Account holder;
    Id contractId;
    Id counterpartyId;
    AXF_OBJ_ContractTermVersion__c term;
    List<AXF_OBJ_FinancialTransaction__c> facts = new List<AXF_OBJ_FinancialTransaction__c>();
  }

  private static User actor() {
    return [SELECT Id FROM User WHERE Alias = 'axf65g' LIMIT 1];
  }

  @TestSetup
  static void setup() {
    User actor = new User(
      Alias = 'axf65g',
      Email = 'axf65g@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Billing Gestor',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
      .Id,
      Username = 'axf65g.' + System.now().getTime() + '@example.invalid'
    );
    insert actor;
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet permission : [
      SELECT Id
      FROM PermissionSet
      WHERE
        Name IN (
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_FinancialEntry',
          'AXF_PS_Realization'
        )
    ]) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = actor.Id,
          PermissionSetId = permission.Id
        )
      );
    }
    insert assignments;
    User outsider = actor.clone(false, false, false, false);
    outsider.Alias = 'axf65o';
    outsider.Username = 'axf65o.' + System.now().getTime() + '@example.invalid';
    insert outsider;
    insert new PermissionSetAssignment(
      AssigneeId = outsider.Id,
      PermissionSetId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'AXF_PS_GestorFinanceiro'
      ]
      .Id
    );
  }

  private static Account makeAccount(String name) {
    Account acc = new Account(
      Name = name,
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
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

  private static Fixture makeFixture(String name, String model) {
    Fixture fixture = new Fixture();
    fixture.holder = makeAccount(name);
    AXF_OBJ_Counterparty__c cpty = makeCounterparty('Cliente ' + name);
    fixture.counterpartyId = cpty.Id;
    AXF_OBJ_CounterpartyEntityRelationship__c rel = new AXF_OBJ_CounterpartyEntityRelationship__c(
      AXF_CER_LKP_Counterparty__c = cpty.Id,
      AXF_CER_LKP_Account__c = fixture.holder.Id,
      AXF_CER_PKL_Role__c = 'SUPPLIER',
      AXF_CER_PKL_Status__c = 'ACTIVE',
      AXF_CER_TXT_EntitySpecificDisplay__c = name,
      AXF_CER_EXI_RelationshipKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'CER', cpty.Id, fixture.holder.Id, 'SUPPLIER' }
      ),
      AXF_CER_NUM_Version__c = 1
    );
    insert rel;
    ALT_CLS_ContractService.ContractInputDTO input = new ALT_CLS_ContractService.ContractInputDTO();
    input.accountId = fixture.holder.Id;
    input.relationshipId = rel.Id;
    input.contractCode = 'CTR-' + Datetime.now().getTime() + '-' + name;
    input.title = 'Contrato ' + name;
    input.contractType = 'EXPENSE';
    input.currencyIsoCode = 'BRL';
    input.startDate = Date.today().addMonths(-1);
    input.endDate = Date.today().addMonths(11);
    ALT_CLS_ContractService.OperationResultDTO created = new ALT_CLS_ContractService()
      .createDraftContract(input);
    Assert.isTrue(created.success, 'Contrato de teste criado.');
    fixture.contractId = created.contractId;
    fixture.term = new AXF_OBJ_ContractTermVersion__c(
      AXF_CTV_LKP_Contract__c = fixture.contractId,
      AXF_CTV_NUM_Revision__c = 1,
      AXF_CTV_PKL_Status__c = 'ACTIVE',
      AXF_CTV_PKL_RemunerationModel__c = model,
      AXF_CTV_CUR_ContractedAmount__c = 1000,
      AXF_CTV_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CTV_DAT_EffectiveFrom__c = Date.today().addMonths(-1),
      AXF_CTV_NUM_Version__c = 1
    );
    insert fixture.term;
    return fixture;
  }

  private static AXF_OBJ_FinancialTransaction__c makeOccurrence(
    Fixture fixture,
    String key,
    Decimal amount,
    String iso,
    Date day,
    Boolean withSnapshot
  ) {
    AXF_OBJ_FinancialTransaction__c ftx = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = fixture.holder.Id,
      AXF_FTX_LKP_Contract__c = fixture.contractId,
      AXF_FTX_NUM_Magnitude__c = amount,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = iso,
      AXF_FTX_DAT_PurchaseDate__c = day,
      AXF_FTX_DAT_DueDate__c = day,
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_TXT_ScheduleGroupKey__c = key,
      AXF_FTX_NUM_Sequence__c = 1,
      AXF_FTX_EXI_ClientRequestId__c = 'ftx-' + Datetime.now().getTime() + key,
      AXF_FTX_EXI_PlanIdentityHash__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'ftx-plan-v1', key, 1 }
      )
    );
    insert ftx;
    if (withSnapshot) {
      ALT_CLS_ContractSnapshotService.SnapshotInputDTO input = new ALT_CLS_ContractSnapshotService.SnapshotInputDTO();
      input.financialTransactionId = ftx.Id;
      input.termVersionId = fixture.term.Id;
      new ALT_CLS_ContractSnapshotService().applyToOccurrence(input);
    }
    fixture.facts.add(ftx);
    return [
      SELECT
        Id,
        AXF_FTX_LKP_ContractApplicationSnapshot__c,
        AXF_FTX_NUM_Magnitude__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id = :ftx.Id
    ];
  }

  private static Id makeApprovedWork(Fixture fixture, Decimal quantity) {
    ALT_CLS_WorkRecordService service = new ALT_CLS_WorkRecordService();
    ALT_CLS_WorkRecordService.WorkRecordInputDTO input = new ALT_CLS_WorkRecordService.WorkRecordInputDTO();
    input.contractId = fixture.contractId;
    input.startDate = Date.today().toStartOfMonth();
    input.endDate = Date.today();
    input.quantity = quantity;
    input.rate = 100;
    input.currencyIsoCode = 'BRL';
    ALT_CLS_WorkRecordService.WorkRecordDetailDTO created = service.registerWorkRecord(
      input
    );
    service.submitWorkRecord(created.workRecordId);
    service.decideWorkRecord(created.workRecordId, true, 'Aprovado');
    return created.workRecordId;
  }

  private static ALT_CLS_BillingDraftService.ComposeInput request(
    Fixture fixture,
    List<AXF_OBJ_FinancialTransaction__c> facts,
    String key
  ) {
    ALT_CLS_BillingDraftService.ComposeInput input = new ALT_CLS_BillingDraftService.ComposeInput();
    input.accountId = fixture.holder.Id;
    input.contractId = fixture.contractId;
    input.counterpartyId = fixture.counterpartyId;
    input.documentKind = 'GENERIC_INVOICE';
    input.seriesKey = key;
    input.periodStart = Date.today().toStartOfMonth();
    input.periodEnd = Date.today().toStartOfMonth().addMonths(1).addDays(-1);
    input.currencyIso = 'BRL';
    input.clientRequestId = 'req-' + key;
    input.lines = new List<ALT_CLS_BillingDraftService.LineInput>();
    for (AXF_OBJ_FinancialTransaction__c fact : facts) {
      ALT_CLS_BillingDraftService.LineInput line = new ALT_CLS_BillingDraftService.LineInput();
      line.financialTransactionId = fact.Id;
      line.snapshotId = fact.AXF_FTX_LKP_ContractApplicationSnapshot__c;
      input.lines.add(line);
    }
    return input;
  }

  private static ALT_CLS_BillingDraftService.BillingDraftException composeExpectingFailure(
    ALT_CLS_BillingDraftService.ComposeInput input
  ) {
    try {
      new ALT_CLS_BillingDraftService().compose(input);
      Assert.fail('Composicao deveria falhar.');
    } catch (ALT_CLS_BillingDraftService.BillingDraftException expected) {
      return expected;
    }
    return null;
  }

  private static Set<String> reasons(
    ALT_CLS_BillingDraftService.BillingDraftException failure
  ) {
    Set<String> result = new Set<String>();
    for (ALT_CLS_BillingDraftService.LineIssue issue : failure.issues) {
      result.add(issue.reason);
    }
    return result;
  }

  @IsTest
  static void composesCompatibleDraftWithWorkAllocationAndConservedTotal() {
    System.runAs(actor()) {
      Fixture fixture = makeFixture('Titular A', 'HOURLY');
      AXF_OBJ_FinancialTransaction__c first = makeOccurrence(
        fixture,
        'a1',
        1000,
        'BRL',
        Date.today(),
        true
      );
      AXF_OBJ_FinancialTransaction__c second = makeOccurrence(
        fixture,
        'a2',
        250.5,
        'BRL',
        Date.today(),
        true
      );
      Id workId = makeApprovedWork(fixture, 50);
      ALT_CLS_BillingDraftService.ComposeInput input = request(
        fixture,
        new List<AXF_OBJ_FinancialTransaction__c>{ first, second },
        '2026-09'
      );
      ALT_CLS_BillingDraftService.WorkAllocationInput allocation = new ALT_CLS_BillingDraftService.WorkAllocationInput();
      allocation.workRecordId = workId;
      allocation.quantity = 30;
      input.lines[0]
        .workAllocations = new List<ALT_CLS_BillingDraftService.WorkAllocationInput>{
        allocation
      };
      ALT_CLS_BillingDraftService service = new ALT_CLS_BillingDraftService();

      Test.startTest();
      List<ALT_CLS_BillingDraftService.Candidate> candidates = service.listCandidates(
        fixture.contractId,
        input.periodStart,
        input.periodEnd,
        'BRL'
      );
      Id documentId = service.compose(input);
      Id replay = service.compose(input);
      Test.stopTest();

      Assert.areEqual(2, candidates.size());
      Assert.isTrue(candidates[0].eligible && candidates[1].eligible);
      Assert.areEqual(
        documentId,
        replay,
        'Mesma chave e payload = mesmo documento.'
      );
      ALT_CLS_BillingDraftService.DraftView view = service.read(documentId);
      Assert.areEqual('DRAFT', view.state);
      Assert.areEqual('OPEN', view.lifecycle);
      Assert.areEqual('DRAFT', view.presentationState);
      Assert.areEqual(2, view.lines.size());
      Assert.areEqual(1250.50, view.totalAmount);
      Assert.areEqual(
        view.totalAmount,
        view.linesTotal,
        'Soma conserva o total.'
      );
      Assert.areEqual(2, view.lineCount);
      Assert.areEqual(
        first.AXF_FTX_LKP_ContractApplicationSnapshot__c,
        view.lines[0].snapshotId
      );
      Assert.areEqual('HOURLY', view.lines[0].lineType);
      Assert.areEqual(1, view.lines[0].workAllocations.size());
      Assert.areEqual(30, view.lines[0].workAllocations[0].quantity);
      Assert.areEqual(3000, view.lines[0].workAllocations[0].amount);
      Assert.isTrue(view.summary.contains('"lineCount":2'));
      List<ALT_CLS_BillingDraftService.WorkRecordView> work = service.listApprovedWork(
        fixture.contractId
      );
      Assert.areEqual(
        20,
        work[0].remainingQuantity,
        'Saldo aprovado consumido.'
      );
      Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_BillingDocument__c]);
      AXF_OBJ_BillingDocumentWorkAllocation__c persisted = [
        SELECT Id
        FROM AXF_OBJ_BillingDocumentWorkAllocation__c
        LIMIT 1
      ];
      persisted.AXF_BWA_NUM_AllocatedQuantity__c = 1;
      Assert.isFalse(
        Database.update(persisted, false).isSuccess(),
        'Alocacao so muda pelo servico.'
      );
      Assert.isFalse(
        Database.delete(persisted, false).isSuccess(),
        'Alocacao nao pode ser excluida.'
      );
      AXF_OBJ_BillingDocumentLine__c persistedLine = new AXF_OBJ_BillingDocumentLine__c(
        Id = view.lines[0].lineId,
        AXF_BDL_CUR_Amount__c = 1
      );
      Assert.isFalse(
        Database.update(persistedLine, false).isSuccess(),
        'Linha so muda pelo servico.'
      );

      // Lancamentos ja faturados deixam de ser elegiveis; payload divergente conflita.
      candidates = service.listCandidates(
        fixture.contractId,
        input.periodStart,
        input.periodEnd,
        'BRL'
      );
      Assert.isFalse(candidates[0].eligible);
      Assert.isTrue(candidates[0].reasons.contains('ALREADY_BILLED'));
      input.seriesKey = '2026-10';
      Assert.areEqual('CONFLICT', composeExpectingFailure(input).code);
    }
  }

  @IsTest
  static void incompatibleLinesAreExplainedAndNothingIsPersisted() {
    System.runAs(actor()) {
      Fixture fixture = makeFixture('Titular B', 'FIXED');
      Fixture other = makeFixture('Titular C', 'FIXED');
      AXF_OBJ_FinancialTransaction__c good = makeOccurrence(
        fixture,
        'b1',
        100,
        'BRL',
        Date.today(),
        true
      );
      AXF_OBJ_FinancialTransaction__c foreignCurrency = makeOccurrence(
        fixture,
        'b2',
        100,
        'USD',
        Date.today(),
        true
      );
      AXF_OBJ_FinancialTransaction__c outsidePeriod = makeOccurrence(
        fixture,
        'b3',
        100,
        'BRL',
        Date.today().addMonths(3),
        true
      );
      AXF_OBJ_FinancialTransaction__c noSnapshot = makeOccurrence(
        fixture,
        'b4',
        100,
        'BRL',
        Date.today(),
        false
      );
      AXF_OBJ_FinancialTransaction__c otherContract = makeOccurrence(
        other,
        'c1',
        100,
        'BRL',
        Date.today(),
        true
      );
      ALT_CLS_BillingDraftService.ComposeInput input = request(
        fixture,
        new List<AXF_OBJ_FinancialTransaction__c>{
          good,
          foreignCurrency,
          outsidePeriod,
          noSnapshot,
          otherContract,
          good
        },
        '2026-09'
      );

      Test.startTest();
      ALT_CLS_BillingDraftService.BillingDraftException failure = composeExpectingFailure(
        input
      );
      List<ALT_CLS_BillingDraftService.Candidate> candidates = new ALT_CLS_BillingDraftService()
        .listCandidates(
          fixture.contractId,
          input.periodStart,
          input.periodEnd,
          'BRL'
        );
      Test.stopTest();

      Assert.areEqual('INCOMPATIBLE_LINES', failure.code);
      Set<String> explained = reasons(failure);
      Assert.isTrue(
        explained.contains('BLOCKED_FX'),
        'Moeda diferente bloqueia sem converter.'
      );
      Assert.isTrue(explained.contains('PERIOD_MISMATCH'));
      Assert.isTrue(explained.contains('SNAPSHOT_MISSING'));
      Assert.isTrue(explained.contains('CONTRACT_MISMATCH'));
      Assert.isTrue(explained.contains('DUPLICATE_LINE'));
      Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_BillingDocument__c]);
      Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_BillingDocumentLine__c]);
      Assert.areEqual(4, candidates.size(), 'So os lancamentos do contrato.');
      Integer eligible = 0;
      for (ALT_CLS_BillingDraftService.Candidate candidate : candidates) {
        if (candidate.eligible) {
          eligible++;
        }
      }
      Assert.areEqual(1, eligible);
    }
  }

  @IsTest
  static void typeMismatchAndWorkOverAllocationAreRejectedAtomically() {
    System.runAs(actor()) {
      Fixture fixture = makeFixture('Titular D', 'FIXED');
      AXF_OBJ_FinancialTransaction__c fixed = makeOccurrence(
        fixture,
        'd1',
        100,
        'BRL',
        Date.today(),
        true
      );
      AXF_OBJ_ContractTermVersion__c hourly = fixture.term.clone(
        false,
        false,
        false,
        false
      );
      hourly.AXF_CTV_NUM_Revision__c = 2;
      hourly.AXF_CTV_PKL_RemunerationModel__c = 'HOURLY';
      hourly.AXF_CTV_PKL_Status__c = 'DRAFT';
      insert hourly;
      AXF_OBJ_FinancialTransaction__c hourlyFact = makeOccurrence(
        fixture,
        'd2',
        100,
        'BRL',
        Date.today(),
        false
      );
      ALT_CLS_ContractSnapshotService.SnapshotInputDTO snapshotInput = new ALT_CLS_ContractSnapshotService.SnapshotInputDTO();
      snapshotInput.financialTransactionId = hourlyFact.Id;
      snapshotInput.termVersionId = hourly.Id;
      Boolean hourlySnapshot = true;
      try {
        new ALT_CLS_ContractSnapshotService().applyToOccurrence(snapshotInput);
      } catch (Exception draftTerm) {
        hourlySnapshot = false;
      }
      Id workId = makeApprovedWork(fixture, 10);
      ALT_CLS_BillingDraftService.ComposeInput input = request(
        fixture,
        new List<AXF_OBJ_FinancialTransaction__c>{ fixed },
        '2026-09'
      );
      ALT_CLS_BillingDraftService.WorkAllocationInput allocation = new ALT_CLS_BillingDraftService.WorkAllocationInput();
      allocation.workRecordId = workId;
      allocation.quantity = 11;
      input.lines[0]
        .workAllocations = new List<ALT_CLS_BillingDraftService.WorkAllocationInput>{
        allocation
      };

      Test.startTest();
      ALT_CLS_BillingDraftService.BillingDraftException failure = composeExpectingFailure(
        input
      );
      Test.stopTest();

      Assert.isTrue(reasons(failure).contains('WORK_OVER_ALLOCATED'));
      Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_BillingDocument__c]);
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_BillingDocumentWorkAllocation__c]
      );
      if (hourlySnapshot) {
        hourlyFact = [
          SELECT Id, AXF_FTX_LKP_ContractApplicationSnapshot__c
          FROM AXF_OBJ_FinancialTransaction__c
          WHERE Id = :hourlyFact.Id
        ];
        input = request(
          fixture,
          new List<AXF_OBJ_FinancialTransaction__c>{ fixed, hourlyFact },
          '2026-11'
        );
        Assert.isTrue(
          reasons(composeExpectingFailure(input)).contains('TYPE_MISMATCH')
        );
      }
    }
  }

  @IsTest
  static void guardsBlockDirectWritesDeletesAndInvalidTransitions() {
    System.runAs(actor()) {
      Fixture fixture = makeFixture('Titular E', 'FIXED');
      AXF_OBJ_FinancialTransaction__c fact = makeOccurrence(
        fixture,
        'e1',
        100,
        'BRL',
        Date.today(),
        true
      );
      ALT_CLS_BillingDraftService service = new ALT_CLS_BillingDraftService();
      Id documentId = service.compose(
        request(
          fixture,
          new List<AXF_OBJ_FinancialTransaction__c>{ fact },
          '2026-09'
        )
      );
      ALT_CLS_BillingDraftService.DraftView view = service.read(documentId);

      Test.startTest();
      AXF_OBJ_BillingDocumentLine__c forged = new AXF_OBJ_BillingDocumentLine__c(
        AXF_BDL_MDR_DocumentVersion__c = view.versionId,
        AXF_BDL_LKP_FinancialTransaction__c = fact.Id,
        AXF_BDL_LKP_ContractApplicationSnapshot__c = fact.AXF_FTX_LKP_ContractApplicationSnapshot__c,
        AXF_BDL_NUM_LineNumber__c = 9,
        AXF_BDL_EXI_LineKey__c = view.versionId + ':9',
        AXF_BDL_PKL_LineType__c = 'FIXED',
        AXF_BDL_CUR_Amount__c = 1,
        AXF_BDL_TXT_CurrencyIsoCode__c = 'BRL'
      );
      Assert.isFalse(
        Database.insert(forged, false).isSuccess(),
        'Linha so nasce pelo servico.'
      );
      Assert.isFalse(
        Database.delete(
            new AXF_OBJ_BillingDocumentLine__c(Id = view.lines[0].lineId),
            false
          )
          .isSuccess(),
        'Linha nao pode ser excluida.'
      );
      Assert.isFalse(
        Database.delete(
            new AXF_OBJ_BillingDocumentVersion__c(Id = view.versionId),
            false
          )
          .isSuccess(),
        'Versao nao pode ser excluida.'
      );
      Assert.isFalse(
        Database.delete(new AXF_OBJ_BillingDocument__c(Id = documentId), false)
          .isSuccess(),
        'Documento nao pode ser excluido.'
      );
      Assert.isFalse(
        Database.update(
            new AXF_OBJ_BillingDocumentVersion__c(
              Id = view.versionId,
              AXF_BDV_PKL_State__c = 'ISSUED'
            ),
            false
          )
          .isSuccess(),
        'DRAFT -> ISSUED nao e transicao valida.'
      );
      Assert.isTrue(
        Database.update(
            new AXF_OBJ_BillingDocumentVersion__c(
              Id = view.versionId,
              AXF_BDV_PKL_State__c = 'REVIEWED'
            ),
            false
          )
          .isSuccess(),
        'DRAFT -> REVIEWED e permitido.'
      );
      Assert.isFalse(
        Database.update(
            new AXF_OBJ_BillingDocument__c(
              Id = documentId,
              AXF_BDO_TXT_SeriesKey__c = 'other'
            ),
            false
          )
          .isSuccess(),
        'Identidade do documento e imutavel.'
      );
      Assert.isTrue(
        Database.update(
            new AXF_OBJ_BillingDocument__c(
              Id = documentId,
              AXF_BDO_NUM_Version__c = 2
            ),
            false
          )
          .isSuccess(),
        'Alteracao de versao otimista e permitida.'
      );
      Assert.isTrue(
        Database.update(
            new AXF_OBJ_BillingDocument__c(
              Id = documentId,
              AXF_BDO_PKL_Lifecycle__c = 'CANCELLED'
            ),
            false
          )
          .isSuccess(),
        'OPEN -> CANCELLED e permitido.'
      );
      Assert.isFalse(
        Database.update(
            new AXF_OBJ_BillingDocument__c(
              Id = documentId,
              AXF_BDO_PKL_Lifecycle__c = 'OPEN'
            ),
            false
          )
          .isSuccess(),
        'CANCELLED e terminal.'
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void deniedUserCannotComposeReadOrDiscoverRecords() {
    System.runAs(actor()) {
      Fixture fixture = makeFixture('Titular F', 'FIXED');
      AXF_OBJ_FinancialTransaction__c fact = makeOccurrence(
        fixture,
        'f1',
        100,
        'BRL',
        Date.today(),
        true
      );
      Id documentId = new ALT_CLS_BillingDraftService()
        .compose(
          request(
            fixture,
            new List<AXF_OBJ_FinancialTransaction__c>{ fact },
            '2026-09'
          )
        );
      User outsider = [SELECT Id FROM User WHERE Alias = 'axf65o' LIMIT 1];
      ALT_CLS_BillingDraftService.ComposeInput input = request(
        fixture,
        new List<AXF_OBJ_FinancialTransaction__c>{ fact },
        '2026-10'
      );

      Test.startTest();
      System.runAs(outsider) {
        ALT_CLS_BillingDraftService service = new ALT_CLS_BillingDraftService();
        Assert.areEqual('NOT_ACCESSIBLE', composeExpectingFailure(input).code);
        try {
          service.read(documentId);
          Assert.fail('Leitura sem acesso deve falhar.');
        } catch (ALT_CLS_BillingDraftService.BillingDraftException expected) {
          Assert.areEqual('NOT_ACCESSIBLE', expected.code);
          Assert.isTrue(
            expected.issues.isEmpty(),
            'Sem detalhes de existencia.'
          );
        }
        try {
          service.listCandidates(fixture.contractId, null, null, 'BRL');
          Assert.fail('Listagem sem acesso deve falhar.');
        } catch (ALT_CLS_BillingDraftService.BillingDraftException expected) {
          Assert.areEqual('NOT_ACCESSIBLE', expected.code);
        }
      }
      Test.stopTest();
      Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_BillingDocument__c]);
    }
  }

  @IsTest
  static void controllerSanitizesFailuresAndReturnsDraftView() {
    System.runAs(actor()) {
      Fixture fixture = makeFixture('Titular G', 'FIXED');
      AXF_OBJ_FinancialTransaction__c fact = makeOccurrence(
        fixture,
        'g1',
        100,
        'BRL',
        Date.today(),
        true
      );
      ALT_CLS_BillingDraftService.ComposeInput input = request(
        fixture,
        new List<AXF_OBJ_FinancialTransaction__c>{ fact },
        '2026-09'
      );

      Test.startTest();
      List<AXF_CLS_CTRL_BillingComposer.ContractOption> contracts = AXF_CLS_CTRL_BillingComposer.getContracts(
        fixture.holder.Id
      );
      List<ALT_CLS_BillingDraftService.Candidate> candidates = AXF_CLS_CTRL_BillingComposer.getCandidates(
        fixture.contractId,
        input.periodStart,
        input.periodEnd,
        'BRL'
      );
      List<ALT_CLS_BillingDraftService.WorkRecordView> work = AXF_CLS_CTRL_BillingComposer.getApprovedWork(
        fixture.contractId
      );
      ALT_CLS_BillingDraftService.DraftView view = AXF_CLS_CTRL_BillingComposer.compose(
        JSON.serialize(input)
      );
      ALT_CLS_BillingDraftService.DraftView again = AXF_CLS_CTRL_BillingComposer.read(
        view.documentId
      );
      String sanitized;
      try {
        AXF_CLS_CTRL_BillingComposer.compose('{"unknown":1}');
      } catch (AuraHandledException expected) {
        sanitized = expected.getMessage();
      }
      String incompatible;
      input.clientRequestId = 'req-other';
      input.seriesKey = '2026-10';
      try {
        AXF_CLS_CTRL_BillingComposer.compose(JSON.serialize(input));
      } catch (AuraHandledException expected) {
        incompatible = expected.getMessage();
      }
      Test.stopTest();

      Assert.areEqual(1, contracts.size());
      Assert.areEqual(fixture.counterpartyId, contracts[0].counterpartyId);
      Assert.areEqual(1, candidates.size());
      Assert.areEqual(0, work.size());
      Assert.areEqual(view.documentId, again.documentId);
      Assert.areEqual(1, again.lines.size());
      Map<String, Object> failure = (Map<String, Object>) JSON.deserializeUntyped(
        sanitized
      );
      Assert.areEqual('INVALID_INPUT', failure.get('code'));
      failure = (Map<String, Object>) JSON.deserializeUntyped(incompatible);
      Assert.areEqual('INCOMPATIBLE_LINES', failure.get('code'));
      Assert.areEqual(1, ((List<Object>) failure.get('issues')).size());
      Assert.isFalse(incompatible.contains('Titular G'), 'Sem PII no erro.');
      Assert.isFalse(
        String.valueOf(AXF_CLS_CTRL_BillingComposer.getAuthorizedEntities()) ==
        null
      );
    }
  }

  @IsTest
  static void controllerRejectsMissingInputAndHidesInaccessibleRecords() {
    Fixture fixture;
    Id documentId;
    System.runAs(actor()) {
      fixture = makeFixture('Titular H', 'FIXED');
      AXF_OBJ_FinancialTransaction__c fact = makeOccurrence(
        fixture,
        'h1',
        100,
        'BRL',
        Date.today(),
        true
      );
      documentId = new ALT_CLS_BillingDraftService()
        .compose(
          request(
            fixture,
            new List<AXF_OBJ_FinancialTransaction__c>{ fact },
            '2026-09'
          )
        );
    }
    List<String> codes = new List<String>();
    User outsider = [SELECT Id FROM User WHERE Alias = 'axf65o' LIMIT 1];
    System.runAs(outsider) {
      Test.startTest();
      try {
        AXF_CLS_CTRL_BillingComposer.read(documentId);
      } catch (AuraHandledException expected) {
        codes.add(code(expected));
      }
      try {
        AXF_CLS_CTRL_BillingComposer.getCandidates(
          fixture.contractId,
          null,
          null,
          'BRL'
        );
      } catch (AuraHandledException expected) {
        codes.add(code(expected));
      }
      try {
        AXF_CLS_CTRL_BillingComposer.getApprovedWork(fixture.contractId);
      } catch (AuraHandledException expected) {
        codes.add(code(expected));
      }
      Assert.areEqual(
        0,
        AXF_CLS_CTRL_BillingComposer.getContracts(fixture.holder.Id).size()
      );
      Test.stopTest();
    }
    Assert.areEqual(
      new List<String>{ 'NOT_ACCESSIBLE', 'NOT_ACCESSIBLE', 'NOT_ACCESSIBLE' },
      codes
    );
    for (Integer i = 0; i < 5; i++) {
      try {
        if (i == 0) {
          AXF_CLS_CTRL_BillingComposer.read(null);
        } else if (i == 1) {
          AXF_CLS_CTRL_BillingComposer.getCandidates(null, null, null, null);
        } else if (i == 2) {
          AXF_CLS_CTRL_BillingComposer.getApprovedWork(null);
        } else if (i == 3) {
          AXF_CLS_CTRL_BillingComposer.getContracts(null);
        } else {
          AXF_CLS_CTRL_BillingComposer.compose('');
        }
        Assert.fail('Entrada ausente deve falhar: ' + i);
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', code(expected), 'Entrada ' + i);
      }
    }
  }

  private static String code(AuraHandledException failure) {
    return (String) ((Map<String, Object>) JSON.deserializeUntyped(
        failure.getMessage()
      ))
      .get('code');
  }
}
