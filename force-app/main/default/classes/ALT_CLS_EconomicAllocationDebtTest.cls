/**
 * @description AXF-129: pagamento por terceiro sem reembolso automatico. Os dois ACs sao sobre a
 * ausencia de comportamento, entao o que se prova aqui e a ausencia e o que a impediria:
 * AC-1 — confirmar o rateio de um pagamento por terceiro nao gera divida: nenhuma pergunta,
 * revisao devedor/recebedor, obrigacao de reembolso, saldo, quitacao parcial ou vencimento. O
 * agregado do rateio (EAS/EA) so expressa cota positiva de uma movimentacao positiva, e o guard
 * recusa qualquer valor ao lado ou alem dela — a forma de um saldo/obrigacao.
 * AC-2 — uma transferencia entre contas permanece duas movimentacoes distintas: cada perna mantem
 * a propria identidade, valor e conta, o rateio ancora em no maximo uma perna (XOR, AXF-126) e
 * nunca no par, e o consolidado soma as duas pernas uma unica vez (par neutro, sem duplicar
 * receita/despesa). Os contratos da AXF-32/InternalTransfer nao sao tocados nem renomeados.
 */
@IsTest
private class ALT_CLS_EconomicAllocationDebtTest {
  /**
   * Vocabulario que o AC-1 proibe no agregado do rateio: divida, obrigacao, saldo, vencimento,
   * quitacao parcial, revisao devedor/recebedor. Nenhum campo, tipo de pergunta ou membro da
   * confirmacao pode carregar esses conceitos.
   */
  private static final List<String> DEBT_CONCEPTS = new List<String>{
    'DEBT',
    'DIVIDA',
    'OWED',
    'OWES',
    'DEBTOR',
    'CREDITOR',
    'REIMBURS',
    'REEMBOLS',
    'REFUND',
    'DUE',
    'VENCIMENTO',
    'BALANCE',
    'SALDO',
    'SETTLE',
    'QUITAC',
    'INSTALLMENT',
    'PARCELAMENTO',
    'REPAY',
    'LIABILITY',
    'PASSIVO',
    'RECEIVABLE',
    'PAYABLE'
  };

  /** Ratified AXF-5 §5 read surface of a set, as the confirmation returns it. */
  private static final List<String> SET_VIEW_MEMBERS = new List<String>{
    'setId',
    'name',
    'factKind',
    'factId',
    'factName',
    'holderAccountId',
    'holderAccountName',
    'revision',
    'state',
    'factMagnitude',
    'currencyIso',
    'totalPercent',
    'version',
    'effectiveAt',
    'shares'
  };
  private static final List<String> SHARE_VIEW_MEMBERS = new List<String>{
    'allocationId',
    'accountId',
    'accountName',
    'percent',
    'magnitude',
    'currencyIso',
    'allocationKey'
  };

  private static User gestor() {
    return [SELECT Id FROM User WHERE Alias = 'axf129g' LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    User gestor = new User(
      Alias = 'axf129g',
      Email = 'axf129g@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Debt Guard',
      LanguageLocaleKey = 'pt_BR',
      LocaleSidKey = 'pt_BR',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = profileId,
      Username = 'axf129g.' + System.now().getTime() + '@example.invalid'
    );
    insert gestor;
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet permission : [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN ('AXF_PS_GestorFinanceiro', 'AXF_PS_FinancialEntry')
    ]) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = gestor.Id,
          PermissionSetId = permission.Id
        )
      );
    }
    insert assignments;
  }

  // ------------------------------------------------------------------ fixtures

  private static Account holder(String name, String recordType) {
    Account result = new Account(
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get(recordType)
        .getRecordTypeId()
    );
    if (recordType == 'AXF_Person') {
      result.LastName = name;
    } else {
      result.Name = name;
    }
    insert result;
    return result;
  }

  private static AXF_OBJ_BankAccount__c bank(Id holderId, String key) {
    AXF_OBJ_BankAccount__c result = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = holderId,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_InstitutionName__c = 'Banco ' + key,
      AXF_BA_TXT_NumberMasked__c = '****' + key,
      AXF_BA_EXI_ManualKey__c = 'manual-' + key + '-' + System.now().getTime(),
      AXF_BA_NUM_Version__c = 0
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_BankAccountTransaction__c movement(
    Id bankId,
    String key,
    Decimal magnitude,
    String direction
  ) {
    AXF_OBJ_BankAccountTransaction__c result = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bankId,
      AXF_BAT_EXI_SourceKey__c = 'bat-' + key + '-' + System.now().getTime(),
      AXF_BAT_PKL_Source__c = 'MANUAL',
      AXF_BAT_DAT_Date__c = Date.today(),
      AXF_BAT_NUM_Magnitude__c = magnitude,
      AXF_BAT_PKL_Direction__c = direction,
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_TXT_Description__c = key,
      AXF_BAT_NUM_Version__c = 0
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_FinancialTransaction__c manualMovement(
    Id holderId,
    String key
  ) {
    AXF_OBJ_FinancialTransaction__c result = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = holderId,
      AXF_FTX_NUM_Magnitude__c = 90,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = Date.today(),
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_EXI_ClientRequestId__c = 'ftx-' +
        key +
        '-' +
        System.now().getTime()
    );
    insert result;
    return result;
  }

  private static ALT_CLS_EconomicAllocationService.ProposeInput proposal(
    Id factId,
    String key,
    Map<Id, Decimal> shares
  ) {
    ALT_CLS_EconomicAllocationService.ProposeInput input = new ALT_CLS_EconomicAllocationService.ProposeInput();
    input.factKind = 'BANK';
    input.factId = factId;
    input.operationKey = key;
    input.shares = new List<ALT_CLS_EconomicAllocationService.ShareInput>();
    for (Id accountId : shares.keySet()) {
      ALT_CLS_EconomicAllocationService.ShareInput share = new ALT_CLS_EconomicAllocationService.ShareInput();
      share.accountId = accountId;
      share.percent = shares.get(accountId);
      input.shares.add(share);
    }
    return input;
  }

  // ------------------------------------------------------------------ helpers

  /** Questions raised anywhere in the org: the single review queue is the only "pergunta" (AD-41). */
  private static Integer questions() {
    return [SELECT COUNT() FROM AXF_OBJ_ReviewItem__c];
  }

  private static Integer sets() {
    return [SELECT COUNT() FROM AXF_OBJ_EconomicAllocationSet__c];
  }

  private static Integer parcels() {
    return [SELECT COUNT() FROM AXF_OBJ_EconomicAllocation__c];
  }

  private static Id storedProjection(Id setId) {
    return [
      SELECT AXF_EAS_LKP_AttributedAccount__c
      FROM AXF_OBJ_EconomicAllocationSet__c
      WHERE Id = :setId
    ]
    .AXF_EAS_LKP_AttributedAccount__c;
  }

  private static String firstError(Database.SaveResult result) {
    Assert.isFalse(result.isSuccess(), 'A escrita deveria ser recusada.');
    return result.getErrors()[0].getMessage();
  }

  /** AC-1: no member of the aggregate may name a debt, an obligation, a balance or a due date. */
  private static void assertNoDebtConcept(Schema.SObjectType type) {
    Schema.DescribeSObjectResult describe = type.getDescribe();
    List<String> names = new List<String>();
    for (Schema.SObjectField field : describe.fields.getMap().values()) {
      Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
      if (fieldDescribe.isCustom()) {
        names.add(fieldDescribe.getName().toUpperCase());
      }
    }
    Assert.isFalse(
      names.isEmpty(),
      'Controle positivo: o agregado tem campos proprios analisados.'
    );
    assertNoDebtConceptIn(names, describe.getName());
  }

  private static void assertNoDebtConceptIn(
    List<String> names,
    String surface
  ) {
    for (String name : names) {
      for (String concept : DEBT_CONCEPTS) {
        Assert.isFalse(
          name.contains(concept),
          'AC-1: ' +
            surface +
            ' nao pode expressar ' +
            concept +
            ' (' +
            name +
            ')'
        );
      }
    }
  }

  /** The confirmed read surface, exactly as the caller receives it. */
  private static List<String> serializedMembers(Object view) {
    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
      JSON.serialize(view)
    );
    List<String> members = new List<String>(body.keySet());
    members.sort();
    return members;
  }

  private static List<String> sorted(List<String> values) {
    List<String> result = values.clone();
    result.sort();
    return result;
  }

  private static ALT_CLS_ConsolidationService.Result consolidate(
    List<Id> accountIds
  ) {
    ALT_CLS_ConsolidationService.ScopeInput input = new ALT_CLS_ConsolidationService.ScopeInput();
    input.accountIds = accountIds;
    return new ALT_CLS_ConsolidationService().consolidate(input);
  }

  private static ALT_CLS_ConsolidationService.Total total(
    ALT_CLS_ConsolidationService.Result result,
    String currencyIso
  ) {
    for (ALT_CLS_ConsolidationService.Total row : result.totals) {
      if (row.currencyIso == currencyIso) {
        return row;
      }
    }
    Assert.fail('Sem total em ' + currencyIso);
    return null;
  }

  private static ALT_CLS_ConsolidationService.Contribution contribution(
    ALT_CLS_ConsolidationService.Result result,
    Id accountId,
    Id sourceId
  ) {
    for (ALT_CLS_ConsolidationService.Contribution row : result.contributions) {
      if (row.accountId == accountId && row.sourceId == sourceId) {
        return row;
      }
    }
    Assert.fail(
      'Sem contribuicao da conta ' + accountId + ' na fonte ' + sourceId
    );
    return null;
  }

  // ------------------------------------------------------------------ AC-1

  /**
   * AC-1: a third-party payment is confirmed as an economic attribution — the expense lands on the
   * person/company that assumed it — and that difference in holders produces no debt at all: no
   * question, no debtor/creditor review, no reimbursement obligation, no balance, no partial
   * settlement, no due date.
   */
  @IsTest
  static void thirdPartyPaymentConfirmationCreatesNoDebtQuestionOrObligation() {
    System.runAs(gestor()) {
      Account payer = holder('Pagador Terceiro', 'AXF_Person');
      Account thirdParty = holder('Beneficiario Terceiro', 'AXF_Business');
      AXF_OBJ_BankAccountTransaction__c fact = movement(
        bank(payer.Id, 't1').Id,
        't1',
        300,
        'DEBIT'
      );
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Assert.areEqual(
        0,
        questions(),
        'Pre-condicao: nada pergunta antes do rateio.'
      );
      Test.startTest();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          fact.Id,
          'op-129-1',
          new Map<Id, Decimal>{ thirdParty.Id => 100 }
        )
      );
      ALT_CLS_EconomicAllocationService.SetView confirmed = service.confirm(
        draft.setId,
        draft.version,
        'op-129-1c'
      );
      Test.stopTest();
      // Positive control: the third-party payment really was attributed to the third party.
      Assert.areEqual('CONFIRMED', confirmed.state);
      Assert.areEqual(100, confirmed.totalPercent);
      Assert.areEqual(payer.Id, confirmed.holderAccountId);
      Assert.areNotEqual(payer.Id, thirdParty.Id);
      Assert.areEqual(
        thirdParty.Id,
        storedProjection(confirmed.setId),
        'O terceiro assume a despesa pela atribuicao economica.'
      );
      Assert.areEqual(1, confirmed.shares.size());
      Assert.areEqual(
        300,
        confirmed.shares[0].magnitude,
        'A parcela e uma cota da movimentacao: positiva e igual ao fato.'
      );
      // AC-1: nothing asks a question and nothing records a debt, a balance or a due date.
      Assert.areEqual(
        0,
        questions(),
        'AC-1: confirmar um pagamento por terceiro nao abre pergunta, revisao de devedor/recebedor nem obrigacao de reembolso.'
      );
      Assert.areEqual(1, sets(), 'O unico efeito e o conjunto confirmado.');
      Assert.areEqual(1, parcels(), 'E a sua unica parcela: nenhum saldo.');
      List<String> questionTypes = new List<String>();
      for (
        Schema.PicklistEntry entry : AXF_OBJ_ReviewItem__c.AXF_RVI_PKL_Type__c.getDescribe()
          .getPicklistValues()
      ) {
        questionTypes.add(entry.getValue().toUpperCase());
      }
      Assert.isFalse(
        questionTypes.isEmpty(),
        'Controle positivo: ha tipos de pergunta.'
      );
      assertNoDebtConceptIn(questionTypes, 'a fila de revisao');
      assertNoDebtConceptIn(
        new List<String>(ALT_CLS_ReviewQueueService.SUPPORTED_TYPES),
        'os tipos de pergunta aceitos'
      );
      assertNoDebtConcept(AXF_OBJ_EconomicAllocationSet__c.SObjectType);
      assertNoDebtConcept(AXF_OBJ_EconomicAllocation__c.SObjectType);
      Assert.areEqual(
        sorted(SET_VIEW_MEMBERS),
        serializedMembers(confirmed),
        'AC-1: a confirmacao nao expoe vencimento, saldo, quitacao parcial nem obrigacao.'
      );
      Assert.areEqual(
        sorted(SHARE_VIEW_MEMBERS),
        serializedMembers(confirmed.shares[0]),
        'AC-1: a parcela expoe somente a cota.'
      );
    }
  }

  /**
   * AC-1 negative path: the only way an allocation could express an amount that someone owes is an
   * amount that does not fit the movement it claims to share. The guard refuses it — and a set that
   * carries no positive movement at all — even for a writer already inside the service window, so
   * no debt or balance can be manufactured through the aggregate.
   */
  @IsTest
  static void theAggregateRefusesAnyAmountThatIsNotAShareOfTheMovement() {
    System.runAs(gestor()) {
      Account payer = holder('Pagador Guarda', 'AXF_Person');
      Account other = holder('Outro Guarda Divida', 'AXF_Person');
      AXF_OBJ_BankAccountTransaction__c fact = movement(
        bank(payer.Id, 'g1').Id,
        'g1',
        300,
        'DEBIT'
      );
      AXF_OBJ_FinancialTransaction__c manual = manualMovement(payer.Id, 'g2');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(fact.Id, 'op-129-g1', new Map<Id, Decimal>{ payer.Id => 100 })
      );
      AXF_OBJ_EconomicAllocation__c parcel = [
        SELECT Id, AXF_EA_MDR_AllocationSet__c
        FROM AXF_OBJ_EconomicAllocation__c
        WHERE AXF_EA_MDR_AllocationSet__c = :draft.setId
        LIMIT 1
      ];
      Test.startTest();
      ALT_CLS_EconomicAllocationGuard.beginWrite();
      try {
        Assert.isTrue(
          firstError(
              Database.insert(
                new AXF_OBJ_EconomicAllocationSet__c(
                  AXF_EAS_LKP_BankTransaction__c = fact.Id,
                  AXF_EAS_LKP_HolderAccount__c = payer.Id,
                  AXF_EAS_TXT_FactIdentity__c = 'no-movement',
                  AXF_EAS_NUM_Revision__c = 90,
                  AXF_EAS_EXI_SetKey__c = 'axf129-no-movement',
                  AXF_EAS_NUM_FactMagnitude__c = 0,
                  AXF_EAS_TXT_CurrencyIsoCode__c = 'BRL',
                  AXF_EAS_TXT_OperationKey__c = 'op-129-g9',
                  AXF_EAS_NUM_Version__c = 1
                ),
                false
              )
            )
            .contains('positive movement'),
          'AC-1: sem movimentacao positiva nao ha cota, so um saldo.'
        );
        Assert.isTrue(
          firstError(
              Database.update(
                new AXF_OBJ_EconomicAllocation__c(
                  Id = parcel.Id,
                  AXF_EA_NUM_Magnitude__c = 301
                ),
                false
              )
            )
            .contains('cannot exceed the movement'),
          'AC-1: a parcela nao pode valer mais que a movimentacao que rateia.'
        );
        Assert.isTrue(
          firstError(
              Database.insert(
                new AXF_OBJ_EconomicAllocation__c(
                  AXF_EA_MDR_AllocationSet__c = draft.setId,
                  AXF_EA_LKP_Account__c = other.Id,
                  AXF_EA_NUM_Percent__c = 100,
                  AXF_EA_NUM_Magnitude__c = 400,
                  AXF_EA_TXT_CurrencyIsoCode__c = 'BRL',
                  AXF_EA_PKL_RedactionPolicy__c = 'OWN_SHARE_ONLY',
                  AXF_EA_EXI_AllocationKey__c = 'axf129-beyond'
                ),
                false
              )
            )
            .contains('cannot exceed the movement'),
          'AC-1: nenhum valor existe ao lado ou alem da movimentacao.'
        );
        // A moved fact cannot be asked to carry an obligation either: the XOR still anchors one leg.
        Assert.isTrue(
          firstError(
              Database.insert(
                new AXF_OBJ_EconomicAllocationSet__c(
                  AXF_EAS_LKP_BankTransaction__c = fact.Id,
                  AXF_EAS_LKP_FinancialTransaction__c = manual.Id,
                  AXF_EAS_LKP_HolderAccount__c = payer.Id,
                  AXF_EAS_TXT_FactIdentity__c = 'pair',
                  AXF_EAS_NUM_Revision__c = 91,
                  AXF_EAS_EXI_SetKey__c = 'axf129-pair',
                  AXF_EAS_NUM_FactMagnitude__c = 300,
                  AXF_EAS_TXT_CurrencyIsoCode__c = 'BRL',
                  AXF_EAS_TXT_OperationKey__c = 'op-129-pair',
                  AXF_EAS_NUM_Version__c = 1
                ),
                false
              )
            )
            .contains('fato de origem'),
          'AC-1/AC-2: o rateio ancora uma unica movimentacao, nunca um par.'
        );
      } finally {
        ALT_CLS_EconomicAllocationGuard.endWrite();
      }
      // Positive control: the legitimate draft and its movement were not altered by the refusals.
      Assert.areEqual(1, sets());
      Assert.areEqual(1, parcels());
      ALT_CLS_EconomicAllocationService.SetView stored = service.read(
        draft.setId
      );
      Assert.areEqual('DRAFT', stored.state);
      Assert.areEqual(100, stored.shares[0].percent);
      ALT_CLS_EconomicAllocationService.SetView confirmed = service.confirm(
        draft.setId,
        stored.version,
        'op-129-g1c'
      );
      Test.stopTest();
      Assert.areEqual('CONFIRMED', confirmed.state);
      Assert.areEqual(300, confirmed.shares[0].magnitude);
      Assert.areEqual(0, questions());
    }
  }

  // ------------------------------------------------------------------ AC-2

  /**
   * AC-2: a transfer between accounts is two distinct movements. Each leg keeps its own identity,
   * amount and account; the consolidated scope counts each leg once, so the pair is neutral and no
   * revenue/expense is duplicated by the transfer; and processing it produces no debt and no
   * question.
   */
  @IsTest
  static void aTransferStaysTwoDistinctMovementsWithoutDebtOrDuplicatedTotals() {
    System.runAs(gestor()) {
      Account origin = holder('Titular Origem', 'AXF_Person');
      Account destination = holder('Titular Destino', 'AXF_Business');
      AXF_OBJ_BankAccount__c originBank = bank(origin.Id, 'o1');
      AXF_OBJ_BankAccount__c destinationBank = bank(destination.Id, 'd1');
      AXF_OBJ_BankAccountTransaction__c outLeg = movement(
        originBank.Id,
        'transfer-out',
        500,
        'DEBIT'
      );
      AXF_OBJ_BankAccountTransaction__c inLeg = movement(
        destinationBank.Id,
        'transfer-in',
        500,
        'CREDIT'
      );
      Test.startTest();
      ALT_CLS_ConsolidationService.Result result = consolidate(
        new List<Id>{ origin.Id, destination.Id }
      );
      Test.stopTest();
      // Distinct movement: two facts, two identities, each still in its own account.
      Assert.areNotEqual(
        outLeg.AXF_BAT_EXI_SourceKey__c,
        inLeg.AXF_BAT_EXI_SourceKey__c,
        'AC-2: as duas pernas sao fatos distintos, nunca um registro renomeado.'
      );
      Assert.areEqual(
        originBank.Id,
        [
          SELECT AXF_BAT_MDR_BankAccount__c
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE Id = :outLeg.Id
        ]
        .AXF_BAT_MDR_BankAccount__c
      );
      Assert.areEqual(
        destinationBank.Id,
        [
          SELECT AXF_BAT_MDR_BankAccount__c
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE Id = :inLeg.Id
        ]
        .AXF_BAT_MDR_BankAccount__c
      );
      // No debt and no question arise from processing the transfer.
      Assert.areEqual(0, sets(), 'AC-2: a transferencia nao gera rateio.');
      Assert.areEqual(0, parcels());
      Assert.areEqual(
        0,
        questions(),
        'AC-2: a transferencia nao abre pergunta.'
      );
      // No duplicated revenue/expense: each leg contributes exactly once and the pair is neutral.
      Assert.areEqual(
        ALT_CLS_ConsolidationService.CONFIDENCE_FULL,
        result.confidence,
        'Nenhuma exclusao nem motivo: as duas pernas foram somadas.'
      );
      Assert.areEqual(2, result.contributions.size());
      Assert.areEqual(
        500,
        contribution(result, origin.Id, originBank.Id).outflow
      );
      Assert.areEqual(0, contribution(result, origin.Id, originBank.Id).inflow);
      Assert.areEqual(
        500,
        contribution(result, destination.Id, destinationBank.Id).inflow
      );
      Assert.areEqual(
        0,
        contribution(result, destination.Id, destinationBank.Id).outflow
      );
      ALT_CLS_ConsolidationService.Total brl = total(result, 'BRL');
      Assert.areEqual(
        500,
        brl.inflow,
        'A entrada da transferencia e contada uma vez.'
      );
      Assert.areEqual(500, brl.outflow, 'A saida e contada uma vez.');
      Assert.areEqual(
        0,
        brl.net,
        'O par de transferencia e neutro: nada duplicado.'
      );
      Assert.areEqual(2, brl.factCount);
      Assert.areEqual(2, brl.holderCount);
    }
  }

  /**
   * AC-2 distinction: a third-party payment is an economic attribution of *one* movement, and that
   * attribution never turns the transfer into a renamed refund. The allocation anchors to the leg it
   * paid, the other leg stays untouched as a movement of its own, and the consolidated totals stay
   * neutral — the transfer contributes once per leg and no obligation is recorded anywhere.
   */
  @IsTest
  static void aThirdPartyAttributionIsAShareOfOneLegAndNeverRenamesTheTransfer() {
    System.runAs(gestor()) {
      Account origin = holder('Origem Distinta', 'AXF_Person');
      Account destination = holder('Destino Distinto', 'AXF_Business');
      AXF_OBJ_BankAccount__c originBank = bank(origin.Id, 'o2');
      AXF_OBJ_BankAccount__c destinationBank = bank(destination.Id, 'd2');
      AXF_OBJ_BankAccountTransaction__c outLeg = movement(
        originBank.Id,
        'transfer-out-2',
        500,
        'DEBIT'
      );
      AXF_OBJ_BankAccountTransaction__c inLeg = movement(
        destinationBank.Id,
        'transfer-in-2',
        500,
        'CREDIT'
      );
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      // The destination assumes the leg it received: an economic attribution, not a reimbursement.
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          outLeg.Id,
          'op-129-d1',
          new Map<Id, Decimal>{ destination.Id => 100 }
        )
      );
      ALT_CLS_EconomicAllocationService.SetView confirmed = service.confirm(
        draft.setId,
        draft.version,
        'op-129-d1c'
      );
      Test.stopTest();
      Assert.areEqual('CONFIRMED', confirmed.state);
      AXF_OBJ_EconomicAllocationSet__c anchor = [
        SELECT
          AXF_EAS_LKP_BankTransaction__c,
          AXF_EAS_LKP_CardTransaction__c,
          AXF_EAS_LKP_FinancialTransaction__c
        FROM AXF_OBJ_EconomicAllocationSet__c
        WHERE Id = :confirmed.setId
      ];
      Assert.areEqual(
        outLeg.Id,
        anchor.AXF_EAS_LKP_BankTransaction__c,
        'AC-2: o rateio ancora na perna que pagou.'
      );
      Assert.isNull(anchor.AXF_EAS_LKP_CardTransaction__c);
      Assert.isNull(
        anchor.AXF_EAS_LKP_FinancialTransaction__c,
        'AC-2: o rateio nunca e o par das duas pernas.'
      );
      // The other leg keeps its own identity, amount and no allocation of its own.
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_EconomicAllocationSet__c
          WHERE
            AXF_EAS_LKP_BankTransaction__c = :inLeg.Id
            OR AXF_EAS_LKP_CardTransaction__c = :inLeg.Id
            OR AXF_EAS_LKP_FinancialTransaction__c = :inLeg.Id
        ],
        'AC-2: a outra perna continua movimentacao distinta, sem rateio.'
      );
      Assert.areEqual(
        500,
        [
          SELECT AXF_BAT_NUM_Magnitude__c
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE Id = :inLeg.Id
        ]
        .AXF_BAT_NUM_Magnitude__c,
        'AC-2: o valor original da perna nao muda.'
      );
      // No debt, no balance, no question: only the attribution of one movement.
      Assert.areEqual(1, sets());
      Assert.areEqual(1, parcels());
      Assert.areEqual(0, questions());
      ALT_CLS_ConsolidationService.Result result = consolidate(
        new List<Id>{ origin.Id, destination.Id }
      );
      ALT_CLS_ConsolidationService.Contribution allocated = contribution(
        result,
        destination.Id,
        originBank.Id
      );
      Assert.areEqual(
        'ALLOCATION',
        allocated.attribution,
        'A perna paga e atribuida economicamente, nao vira obrigacao.'
      );
      Assert.areEqual(500, allocated.outflow);
      ALT_CLS_ConsolidationService.Contribution material = contribution(
        result,
        destination.Id,
        destinationBank.Id
      );
      Assert.areEqual(
        'HOLDER',
        material.attribution,
        'A perna recebida continua no proprio titular.'
      );
      Assert.areEqual(500, material.inflow);
      ALT_CLS_ConsolidationService.Total brl = total(result, 'BRL');
      Assert.areEqual(500, brl.inflow);
      Assert.areEqual(500, brl.outflow);
      Assert.areEqual(
        0,
        brl.net,
        'AC-2: a transferencia segue neutra e nao duplica receita/despesa.'
      );
      Assert.areEqual(2, brl.factCount);
    }
  }
}
