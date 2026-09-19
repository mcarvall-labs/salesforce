/**
 * @description AXF-129: pagamento por terceiro nao gera divida automatica (AC-1) e transferencia
 * entre contas e uma movimentacao distinta, nunca um reembolso renomeado (AC-2).
 *
 * AC-1 e uma afirmacao de ausencia, provada em duas frentes.
 * (a) Vocabulario: nenhum campo do agregado (EAS/EA), nenhum tipo de pergunta da fila unica
 * (AD-41) e nenhum membro da superficie de leitura implementada nomeia divida, obrigacao,
 * revisao devedor/credor, saldo, quitacao parcial ou vencimento. O julgamento e por token exato,
 * nunca por substring: DUE nao acusa RESIDUE/OVERDUE e OWED nao acusa ALLOWED/DISALLOWED.
 * (b) Forma: nenhum valor existe ao lado ou alem da movimentacao. Esta entrega NAO adiciona regra
 * ao guard (F1/b): a cerca e o proprio servico, e cada regra e falsificavel sozinha em um metodo
 * independente — percentual fora de (0,100], magnitude declarada diferente da movimentacao
 * ancorada, parcela alem da movimentacao e soma das parcelas alem da movimentacao.
 *
 * AC-2 e provada estruturalmente (duas pernas, ancora XOR, totais consolidados neutros) e tambem
 * pelas rotas reais que poderiam renomear uma transferencia ou chama-la de reembolso: a exclusao
 * por operacao de transferencia e por estorno em ALT_CLS_TransactionObservationService, e a recusa
 * dos papeis TRANSFER/REFUND/INVOICE_PAYMENT em ALT_CLS_SourceLinkService antes de qualquer
 * escrita. Rotear esses papeis e capacidade da AXF-135, que esta entrega nao implementa nem muda.
 */
@IsTest
private class ALT_CLS_EconomicAllocationDebtTest {
  /**
   * Vocabulario que o AC-1 proibe no agregado do rateio: divida, obrigacao de reembolso, revisao
   * devedor/credor, saldo, quitacao parcial, vencimento e o reembolso/estorno que a AC-2 proibe
   * renomear. A lista e fechada e explicita (singular e plural em ingles e portugues) porque o
   * casamento e por token inteiro: sem prefixo, sem radical, sem substring.
   */
  private static final List<String> DEBT_CONCEPTS = new List<String>{
    'DEBT',
    'DEBTS',
    'DIVIDA',
    'DIVIDAS',
    'OBLIGATION',
    'OBLIGATIONS',
    'OBRIGACAO',
    'OBRIGACOES',
    'REIMBURSEMENT',
    'REIMBURSEMENTS',
    'REIMBURSE',
    'REEMBOLSO',
    'REEMBOLSOS',
    'DEBTOR',
    'DEBTORS',
    'DEVEDOR',
    'DEVEDORES',
    'CREDITOR',
    'CREDITORS',
    'CREDOR',
    'CREDORES',
    'OWED',
    'OWES',
    'REFUND',
    'REFUNDS',
    'ESTORNO',
    'ESTORNOS',
    'DUE',
    'DUEDATE',
    'VENCIMENTO',
    'VENCIMENTOS',
    'BALANCE',
    'BALANCES',
    'SALDO',
    'SALDOS',
    'SETTLE',
    'SETTLED',
    'SETTLEMENT',
    'SETTLEMENTS',
    'QUITACAO',
    'QUITACOES',
    'INSTALLMENT',
    'INSTALLMENTS',
    'PARCELAMENTO',
    'PARCELAMENTOS',
    'REPAY',
    'REPAYMENT',
    'LIABILITY',
    'LIABILITIES',
    'PASSIVO',
    'PASSIVOS',
    'RECEIVABLE',
    'RECEIVABLES',
    'PAYABLE',
    'PAYABLES'
  };

  /**
   * F4: os membros que ESTA projecao implementa — nao "a superficie ratificada da §5". A §5
   * ratifica tambem membros do agregado que a view nao projeta (ver as duas listas seguintes);
   * chama-las de contrato ratificado congelaria a lacuna como se fosse o contrato.
   */
  private static final List<String> IMPLEMENTED_SET_VIEW_MEMBERS = new List<String>{
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
  private static final List<String> IMPLEMENTED_SHARE_VIEW_MEMBERS = new List<String>{
    'allocationId',
    'accountId',
    'accountName',
    'percent',
    'magnitude',
    'currencyIso',
    'allocationKey'
  };
  /**
   * F4: ratificados no agregado pela §5 e deliberadamente NAO projetados nesta view. A ausencia e
   * afirmada explicitamente, membro a membro, em vez de ficar implicita na igualdade acima.
   */
  private static final List<String> SET_MEMBERS_NOT_PROJECTED = new List<String>{
    'setKey',
    'activeToken',
    'attributedAccountId',
    'operationKey',
    'confirmOperationKey'
  };
  private static final List<String> SHARE_MEMBERS_NOT_PROJECTED = new List<String>{
    'setId',
    'redactionPolicy'
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
    // AXF_PS_Realization carries AXF_CanRealize, the second capability the source link requires;
    // AXF_PS_GestorFinanceiro carries AXF_CanAllocateEconomically, AXF_CanObserveTransactions and
    // AXF_CanLinkSource.
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
    return movement(bankId, key, magnitude, direction, null, key);
  }

  private static AXF_OBJ_BankAccountTransaction__c movement(
    Id bankId,
    String key,
    Decimal magnitude,
    String direction,
    String operation,
    String description
  ) {
    AXF_OBJ_BankAccountTransaction__c result = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bankId,
      AXF_BAT_EXI_SourceKey__c = 'bat-' + key + '-' + System.now().getTime(),
      AXF_BAT_PKL_Source__c = 'MANUAL',
      AXF_BAT_DAT_Date__c = Date.today(),
      AXF_BAT_NUM_Magnitude__c = magnitude,
      AXF_BAT_PKL_Direction__c = direction,
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_TXT_RawSourceStatus__c = 'POSTED',
      AXF_BAT_TXT_OperationType__c = operation,
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_TXT_Description__c = description,
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

  private static String stateOf(Id setId) {
    return [
      SELECT AXF_EAS_PKL_State__c
      FROM AXF_OBJ_EconomicAllocationSet__c
      WHERE Id = :setId
    ]
    .AXF_EAS_PKL_State__c;
  }

  private static AXF_OBJ_EconomicAllocation__c parcelOf(
    Id setId,
    Id accountId
  ) {
    return [
      SELECT Id, AXF_EA_NUM_Percent__c, AXF_EA_NUM_Magnitude__c
      FROM AXF_OBJ_EconomicAllocation__c
      WHERE
        AXF_EA_MDR_AllocationSet__c = :setId
        AND AXF_EA_LKP_Account__c = :accountId
      LIMIT 1
    ];
  }

  /** A typed refusal whose reasons carry the named code, or a failing assertion naming them. */
  private static void assertRefusedWith(
    List<String> reasons,
    String code,
    String claim
  ) {
    for (String reason : reasons) {
      if (reason == code || reason.startsWith(code + ':')) {
        return;
      }
    }
    Assert.fail(claim + ' (motivos: ' + reasons + ')');
  }

  /** Proposes and fails the test if the service accepted the shares. */
  private static ALT_CLS_EconomicAllocationService.EconomicAllocationException proposeRefusal(
    ALT_CLS_EconomicAllocationService.ProposeInput input
  ) {
    try {
      new ALT_CLS_EconomicAllocationService().propose(input);
    } catch (ALT_CLS_EconomicAllocationService.EconomicAllocationException expected) {
      return expected;
    }
    Assert.fail('O rateio deveria ser recusado: ' + input.operationKey);
    return null;
  }

  /** Confirms and fails the test if the service accepted the confirmation. */
  private static ALT_CLS_EconomicAllocationService.EconomicAllocationException confirmRefusal(
    Id setId,
    Decimal version,
    String operationKey
  ) {
    try {
      new ALT_CLS_EconomicAllocationService()
        .confirm(setId, version, operationKey);
    } catch (ALT_CLS_EconomicAllocationService.EconomicAllocationException expected) {
      return expected;
    }
    Assert.fail('A confirmacao deveria ser recusada: ' + operationKey);
    return null;
  }

  private static String firstError(Database.SaveResult result) {
    Assert.isFalse(result.isSuccess(), 'A escrita deveria ser recusada.');
    return result.getErrors()[0].getMessage();
  }

  /**
   * F3: tokens de um nome — separadores nao alfanumericos e transicoes camelCase (uma maiuscula
   * depois de minuscula ou digito). `AXF_EAS_DAT_DueDate__c` rende AXF, EAS, DAT, DUE e DATE;
   * `TRANSFER_SUGGESTION` rende TRANSFER e SUGGESTION. Nunca substring: RESIDUE, OVERDUE,
   * ALLOWED e DISALLOWED nao rendem DUE nem OWED.
   */
  private static List<String> tokens(String raw) {
    List<String> result = new List<String>();
    if (String.isBlank(raw)) {
      return result;
    }
    String current = '';
    Boolean previousLowerOrDigit = false;
    for (Integer i = 0; i < raw.length(); i++) {
      String ch = raw.substring(i, i + 1);
      if (!ch.isAlphanumeric()) {
        if (current.length() > 0) {
          result.add(current);
        }
        current = '';
        previousLowerOrDigit = false;
        continue;
      }
      Boolean upper =
        ch.equals(ch.toUpperCase()) && !ch.equals(ch.toLowerCase());
      if (current.length() > 0 && upper && previousLowerOrDigit) {
        result.add(current);
        current = '';
      }
      current += ch;
      previousLowerOrDigit = !upper;
    }
    if (current.length() > 0) {
      result.add(current);
    }
    return result;
  }

  /** The first debt token found in any name, described, or null. Exact tokens only (F2/F3). */
  private static String debtTokenViolation(List<String> names) {
    for (String name : names) {
      for (String token : tokens(name)) {
        for (String concept : DEBT_CONCEPTS) {
          if (token.equalsIgnoreCase(concept)) {
            return concept + ' em ' + name;
          }
        }
      }
    }
    return null;
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
    String violation = debtTokenViolation(names);
    Assert.isNull(
      violation,
      'AC-1: ' +
        surface +
        ' nao pode expressar divida, obrigacao, saldo nem vencimento (' +
        violation +
        ')'
    );
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

  private static void assertNotProjected(
    Object view,
    List<String> members,
    String surface
  ) {
    List<String> present = serializedMembers(view);
    for (String member : members) {
      Assert.isFalse(
        present.contains(member),
        'F4: ' +
          surface +
          ' nao projeta ' +
          member +
          ' nesta entrega (ratificado no agregado): ' +
          present
      );
    }
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

  /** A set written straight into the aggregate, declaring whatever magnitude it likes (F1). */
  private static Id forgedSet(
    Id factId,
    Id holderId,
    Decimal declaredMagnitude,
    String key
  ) {
    return Database.insert(
        new AXF_OBJ_EconomicAllocationSet__c(
          AXF_EAS_LKP_BankTransaction__c = factId,
          AXF_EAS_LKP_HolderAccount__c = holderId,
          AXF_EAS_TXT_FactIdentity__c = 'axf129-' + key,
          AXF_EAS_NUM_Revision__c = 90,
          AXF_EAS_EXI_SetKey__c = 'axf129-' + key,
          AXF_EAS_NUM_FactMagnitude__c = declaredMagnitude,
          AXF_EAS_TXT_CurrencyIsoCode__c = 'BRL',
          AXF_EAS_TXT_OperationKey__c = 'op-129-' + key,
          AXF_EAS_NUM_Version__c = 1
        ),
        true
      )
      .getId();
  }

  private static void forgedParcel(
    Id setId,
    Id accountId,
    Decimal percent,
    Decimal magnitude,
    String key
  ) {
    insert new AXF_OBJ_EconomicAllocation__c(
      AXF_EA_MDR_AllocationSet__c = setId,
      AXF_EA_LKP_Account__c = accountId,
      AXF_EA_NUM_Percent__c = percent,
      AXF_EA_NUM_Magnitude__c = magnitude,
      AXF_EA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_EA_PKL_RedactionPolicy__c = 'OWN_SHARE_ONLY',
      AXF_EA_EXI_AllocationKey__c = 'axf129-' + key
    );
  }

  /** The service write window, so a direct write is judged by the guard and not by "use the service". */
  private static void rewriteParcel(
    Id parcelId,
    Decimal percent,
    Decimal magnitude
  ) {
    ALT_CLS_EconomicAllocationGuard.beginWrite();
    try {
      Database.update(
        new AXF_OBJ_EconomicAllocation__c(
          Id = parcelId,
          AXF_EA_NUM_Percent__c = percent,
          AXF_EA_NUM_Magnitude__c = magnitude
        ),
        true
      );
    } finally {
      ALT_CLS_EconomicAllocationGuard.endWrite();
    }
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
      // F4: this is the surface *this view implements*, not the whole ratified §5 surface.
      Assert.areEqual(
        sorted(IMPLEMENTED_SET_VIEW_MEMBERS),
        serializedMembers(confirmed),
        'AC-1: a projecao do conjunto nao expoe vencimento, saldo, quitacao parcial nem obrigacao.'
      );
      Assert.areEqual(
        sorted(IMPLEMENTED_SHARE_VIEW_MEMBERS),
        serializedMembers(confirmed.shares[0]),
        'AC-1: a parcela expoe somente a cota.'
      );
      assertNotProjected(
        confirmed,
        SET_MEMBERS_NOT_PROJECTED,
        'a projecao do conjunto'
      );
      assertNotProjected(
        confirmed.shares[0],
        SHARE_MEMBERS_NOT_PROJECTED,
        'a projecao da parcela'
      );
    }
  }

  /**
   * F3 control: the vocabulary is judged on whole tokens. A debt-shaped name is caught even when it
   * is a segment, and a legitimate unrelated name that merely contains the letters is not —
   * otherwise a future `RESIDUE` or `ALLOWED` would fail a test about allocation debt.
   */
  @IsTest
  static void theDebtVocabularyJudgesTokensAndNotSubstrings() {
    for (
      String name : new List<String>{
        'AXF_EA_NUM_Saldo__c',
        'AXF_EA_TXT_Obligation__c',
        'AXF_EAS_LKP_Credor__c',
        'DEVEDOR_REVIEW',
        'OBRIGACAO',
        'AXF_EA_DAT_DueDate__c',
        'TOTAL_REIMBURSEMENT'
      }
    ) {
      Assert.isNotNull(
        debtTokenViolation(new List<String>{ name }),
        'Vocabulario de divida deveria acusar ' + name
      );
    }
    Assert.isNull(
      debtTokenViolation(
        new List<String>{
          'RESIDUE',
          'OVERDUE',
          'ALLOWED',
          'DISALLOWED',
          'ENDOWED',
          'AXF_EA_NUM_Magnitude__c',
          'AXF_EAS_EXI_SetKey__c',
          'AXF_EAS_EXI_ActiveToken__c',
          'TRANSFER_SUGGESTION',
          'ACCOUNT_MERGE',
          'HOLDER_CONFIRMATION',
          'SOURCE_DELETE'
        }
      ),
      'Nomes legitimos e nao relacionados nao podem ser acusados por substring.'
    );
  }

  /**
   * AC-1 negative path 1/4 — the percentage rule. A share is a fraction of the movement, so a
   * percentage outside (0,100] is refused as a share before anything is written; `propose` is the
   * only path that creates parcels, so no other path can put one there.
   */
  @IsTest
  static void aSharePercentageOutsideThePositiveRangeIsRefusedBeforeAnyWrite() {
    System.runAs(gestor()) {
      Account payer = holder('Pagador Percentual', 'AXF_Person');
      Account thirdParty = holder('Terceiro Percentual', 'AXF_Business');
      AXF_OBJ_BankAccountTransaction__c fact = movement(
        bank(payer.Id, 'p1').Id,
        'p1',
        300,
        'DEBIT'
      );
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.EconomicAllocationException above = proposeRefusal(
        proposal(
          fact.Id,
          'op-129-p120',
          new Map<Id, Decimal>{ thirdParty.Id => 120 }
        )
      );
      Assert.areEqual('INVALID_SHARES', above.code);
      assertRefusedWith(
        above.reasons,
        'NON_POSITIVE_SHARE',
        'AC-1: 120% do movimento nao e uma cota'
      );
      ALT_CLS_EconomicAllocationService.EconomicAllocationException zero = proposeRefusal(
        proposal(
          fact.Id,
          'op-129-p0',
          new Map<Id, Decimal>{ thirdParty.Id => 0 }
        )
      );
      Assert.areEqual('INVALID_SHARES', zero.code);
      assertRefusedWith(
        zero.reasons,
        'NON_POSITIVE_SHARE',
        'AC-1: 0% tambem nao e uma cota'
      );
      // Nothing was written by either refusal, and the movement is untouched.
      Assert.areEqual(
        0,
        sets(),
        'Nenhum conjunto a partir de uma cota invalida.'
      );
      Assert.areEqual(
        0,
        parcels(),
        'Nenhuma parcela a partir de uma cota invalida.'
      );
      Assert.areEqual(
        300,
        [
          SELECT AXF_BAT_NUM_Magnitude__c
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE Id = :fact.Id
        ]
        .AXF_BAT_NUM_Magnitude__c
      );
      // Positive control: 100% of the movement is a share, and it still confirms.
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          fact.Id,
          'op-129-p100',
          new Map<Id, Decimal>{ thirdParty.Id => 100 }
        )
      );
      ALT_CLS_EconomicAllocationService.SetView confirmed = service.confirm(
        draft.setId,
        draft.version,
        'op-129-p100c'
      );
      Test.stopTest();
      Assert.areEqual('CONFIRMED', confirmed.state);
      Assert.areEqual(300, confirmed.shares[0].magnitude);
    }
  }

  /**
   * AC-1 negative path 2/4 — the declared magnitude rule (the F1 defect, stated plainly). A set
   * written inside the write window may declare any fact magnitude it likes; the guard does not
   * trust and cannot validate that field, so the field is not the authority. The confirmation
   * derives the movement from the anchored fact and refuses a set whose declared magnitude is not
   * that movement's own — an amount standing on its own is the shape of a balance, not of a share.
   */
  @IsTest
  static void aDeclaredMagnitudeThatIsNotTheMovementsOwnIsRefused() {
    System.runAs(gestor()) {
      Account payer = holder('Pagador Declarado', 'AXF_Person');
      AXF_OBJ_BankAccountTransaction__c fact = movement(
        bank(payer.Id, 'm1').Id,
        'm1',
        300,
        'DEBIT'
      );
      Id inflated;
      Id withoutMovement;
      Test.startTest();
      ALT_CLS_EconomicAllocationGuard.beginWrite();
      try {
        // 1,000,000 declared against a 300 movement: accepted by the guard's write window.
        inflated = forgedSet(fact.Id, payer.Id, 1000000, 'inflated-set');
        forgedParcel(inflated, payer.Id, 100, 1000000, 'inflated-parcel');
        // 0 declared against the same 300 movement: also accepted there.
        withoutMovement = forgedSet(fact.Id, payer.Id, 0, 'no-movement-set');
      } finally {
        ALT_CLS_EconomicAllocationGuard.endWrite();
      }
      ALT_CLS_EconomicAllocationService.EconomicAllocationException inflatedRefusal = confirmRefusal(
        inflated,
        1,
        'op-129-m1c'
      );
      Assert.areEqual('CONFIRMATION_REJECTED', inflatedRefusal.code);
      assertRefusedWith(
        inflatedRefusal.reasons,
        'FACT_CHANGED',
        'AC-1: a magnitude declarada nao e a movimentacao ancorada'
      );
      ALT_CLS_EconomicAllocationService.EconomicAllocationException emptyRefusal = confirmRefusal(
        withoutMovement,
        1,
        'op-129-m2c'
      );
      Assert.areEqual('CONFIRMATION_REJECTED', emptyRefusal.code);
      assertRefusedWith(
        emptyRefusal.reasons,
        'FACT_CHANGED',
        'AC-1: um conjunto sem movimentacao positiva nao confirma'
      );
      Test.stopTest();
      // Neither forged set became an authority, and nothing asked a question.
      Assert.areEqual('DRAFT', stateOf(inflated));
      Assert.areEqual('DRAFT', stateOf(withoutMovement));
      Assert.areEqual(0, questions());
    }
  }

  /**
   * AC-1 negative path 3/4 — the parcel rule. A parcel changed to an amount beyond its movement
   * cannot be confirmed: the confirmation conserves the movement, so no amount exists beside or
   * beyond it. The legitimate share still confirms once it is restored.
   */
  @IsTest
  static void aShareBeyondTheMovementIsRefusedAtConfirmation() {
    System.runAs(gestor()) {
      Account payer = holder('Pagador Alem', 'AXF_Person');
      AXF_OBJ_BankAccountTransaction__c fact = movement(
        bank(payer.Id, 'a1').Id,
        'a1',
        300,
        'DEBIT'
      );
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(fact.Id, 'op-129-a1', new Map<Id, Decimal>{ payer.Id => 100 })
      );
      AXF_OBJ_EconomicAllocation__c parcel = parcelOf(draft.setId, payer.Id);
      Assert.areEqual(
        300,
        parcel.AXF_EA_NUM_Magnitude__c,
        'Pre-condicao: a cota do servico e a movimentacao.'
      );
      Test.startTest();
      // 100% of the movement carrying 400: an amount beside the movement.
      rewriteParcel(parcel.Id, 100, 400);
      ALT_CLS_EconomicAllocationService.EconomicAllocationException refused = confirmRefusal(
        draft.setId,
        draft.version,
        'op-129-a1c'
      );
      Assert.areEqual('CONFIRMATION_REJECTED', refused.code);
      assertRefusedWith(
        refused.reasons,
        'MAGNITUDE_NOT_CONSERVED',
        'AC-1: a cota nao pode valer mais que a movimentacao'
      );
      Assert.areEqual(
        'DRAFT',
        stateOf(draft.setId),
        'AC-1: a recusa nao deixa autoridade nenhuma.'
      );
      // Positive control: the correct share is untouched by the refusal and still confirms.
      rewriteParcel(parcel.Id, 100, 300);
      ALT_CLS_EconomicAllocationService.SetView confirmed = service.confirm(
        draft.setId,
        draft.version,
        'op-129-a1c'
      );
      Test.stopTest();
      Assert.areEqual('CONFIRMED', confirmed.state);
      Assert.areEqual(300, confirmed.shares[0].magnitude);
      Assert.areEqual(0, questions());
    }
  }

  /**
   * AC-1 negative path 4/4 — the aggregate rule. Two parcels that each fit inside the movement but
   * together exceed it cannot be confirmed: the sum, not the parcel in isolation, has to conserve
   * the movement. This is the aggregate check the removed guard rule never had (F1).
   */
  @IsTest
  static void parcelsThatTogetherExceedTheMovementAreRefusedAtConfirmation() {
    System.runAs(gestor()) {
      Account payer = holder('Pagador Soma', 'AXF_Person');
      Account thirdParty = holder('Terceiro Soma', 'AXF_Business');
      AXF_OBJ_BankAccountTransaction__c fact = movement(
        bank(payer.Id, 's1').Id,
        's1',
        300,
        'DEBIT'
      );
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          fact.Id,
          'op-129-s1',
          new Map<Id, Decimal>{ payer.Id => 60, thirdParty.Id => 40 }
        )
      );
      AXF_OBJ_EconomicAllocation__c mine = parcelOf(draft.setId, payer.Id);
      AXF_OBJ_EconomicAllocation__c theirs = parcelOf(
        draft.setId,
        thirdParty.Id
      );
      Test.startTest();
      // 300 (60%) + 200 (40%): each one fits the 300 movement on its own, the sum does not.
      rewriteParcel(mine.Id, 60, 300);
      rewriteParcel(theirs.Id, 40, 200);
      Decimal mineNow = parcelOf(draft.setId, payer.Id).AXF_EA_NUM_Magnitude__c;
      Decimal theirsNow = parcelOf(draft.setId, thirdParty.Id)
        .AXF_EA_NUM_Magnitude__c;
      Assert.isTrue(
        mineNow <= 300 && theirsNow <= 300,
        'Pre-condicao do caso: nenhuma parcela excede a movimentacao isoladamente.'
      );
      Assert.areEqual(
        500,
        mineNow + theirsNow,
        'Pre-condicao do caso: a soma das parcelas excede a movimentacao.'
      );
      ALT_CLS_EconomicAllocationService.EconomicAllocationException refused = confirmRefusal(
        draft.setId,
        draft.version,
        'op-129-s1c'
      );
      Assert.areEqual('CONFIRMATION_REJECTED', refused.code);
      assertRefusedWith(
        refused.reasons,
        'MAGNITUDE_NOT_CONSERVED',
        'AC-1: a soma das parcelas tem de conservar a movimentacao'
      );
      Assert.areEqual('DRAFT', stateOf(draft.setId));
      // Positive control: the shares the service proposed conserve the movement and confirm.
      rewriteParcel(mine.Id, 60, 180);
      rewriteParcel(theirs.Id, 40, 120);
      ALT_CLS_EconomicAllocationService.SetView confirmed = service.confirm(
        draft.setId,
        draft.version,
        'op-129-s1c'
      );
      Test.stopTest();
      Assert.areEqual('CONFIRMED', confirmed.state);
      Assert.areEqual(
        300,
        confirmed.shares[0].magnitude + confirmed.shares[1].magnitude
      );
      Assert.areEqual(0, questions());
    }
  }

  // ------------------------------------------------------------------ AC-2

  /**
   * AC-2, structural: a transfer between accounts is two distinct movements. Each leg keeps its
   * own identity, amount and account; the consolidated scope counts each leg once, so the pair is
   * neutral and no revenue/expense is duplicated by the transfer; and processing it produces no
   * debt and no question.
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
   * AC-2, structural: a third-party payment is an economic attribution of *one* movement and that
   * attribution never turns the transfer into a renamed refund. The allocation anchors to the leg
   * it paid, the other leg stays untouched as a movement of its own, and the consolidated totals
   * stay neutral — the transfer contributes once per leg and no obligation is recorded anywhere.
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

  /**
   * AC-2 through the real classification path: a transfer operation and a reversal are never
   * observed as spend. The leg leaves the observation as EXCLUDED — TRANSFER by operation type,
   * REVERSAL by description — so neither the transfer nor a refund-like leg can ever be promoted
   * to a consumption expense or to an allocation. This is
   * ALT_CLS_TransactionObservationService's own exclusion, exercised here, not asserted
   * structurally.
   */
  @IsTest
  static void aTransferOperationIsNeverObservedAsSpendNorAsARefund() {
    System.runAs(gestor()) {
      Account holder = holder('Titular Observado', 'AXF_Business');
      AXF_OBJ_BankAccount__c account = bank(holder.Id, 'v1');
      AXF_OBJ_BankAccountTransaction__c transfer = movement(
        account.Id,
        'transfer-leg',
        500,
        'DEBIT',
        'PIX',
        'PIX ENVIADO TITULAR DESTINO'
      );
      AXF_OBJ_BankAccountTransaction__c refund = movement(
        account.Id,
        'refund-leg',
        500,
        'DEBIT',
        'OUTROS',
        'ESTORNO DE COMPRA'
      );
      ALT_CLS_TransactionObservationService.ObserveInput input = new ALT_CLS_TransactionObservationService.ObserveInput();
      input.accountId = holder.Id;
      input.factIds = new List<Id>{ transfer.Id, refund.Id };
      Test.startTest();
      ALT_CLS_TransactionObservationService.ObserveResult result = new ALT_CLS_TransactionObservationService()
        .observe(input);
      Test.stopTest();
      Assert.areEqual(2, result.created);
      Assert.areEqual(
        2,
        result.byEligibility.get(
          ALT_CLS_TransactionObservationService.EXCLUDED
        ),
        'AC-2: nem a transferencia nem o estorno viram gasto observado.'
      );
      Assert.areEqual(
        0,
        result.byEligibility.get(ALT_CLS_TransactionObservationService.ELIGIBLE)
      );
      AXF_OBJ_TransactionObservation__c transferObservation = [
        SELECT
          AXF_TOB_PKL_Eligibility__c,
          AXF_TOB_PKL_ExclusionReason__c,
          AXF_TOB_PKL_ClassificationProvenance__c
        FROM AXF_OBJ_TransactionObservation__c
        WHERE AXF_TOB_LKP_BankTransaction__c = :transfer.Id
        LIMIT 1
      ];
      Assert.areEqual(
        'EXCLUDED',
        transferObservation.AXF_TOB_PKL_Eligibility__c
      );
      Assert.areEqual(
        'TRANSFER',
        transferObservation.AXF_TOB_PKL_ExclusionReason__c,
        'AC-2: a operacao de transferencia e excluida como transferencia.'
      );
      Assert.areEqual(
        'OPERATION_TYPE',
        transferObservation.AXF_TOB_PKL_ClassificationProvenance__c
      );
      AXF_OBJ_TransactionObservation__c refundObservation = [
        SELECT
          AXF_TOB_PKL_Eligibility__c,
          AXF_TOB_PKL_ExclusionReason__c,
          AXF_TOB_PKL_ClassificationProvenance__c
        FROM AXF_OBJ_TransactionObservation__c
        WHERE AXF_TOB_LKP_BankTransaction__c = :refund.Id
        LIMIT 1
      ];
      Assert.areEqual('EXCLUDED', refundObservation.AXF_TOB_PKL_Eligibility__c);
      Assert.areEqual(
        'REVERSAL',
        refundObservation.AXF_TOB_PKL_ExclusionReason__c,
        'AC-2: um estorno nunca vira gasto.'
      );
      Assert.areEqual(
        'DESCRIPTION_RULE',
        refundObservation.AXF_TOB_PKL_ClassificationProvenance__c
      );
      Assert.areEqual(0, sets());
      Assert.areEqual(0, parcels());
      Assert.areEqual(0, questions());
    }
  }

  /**
   * AC-2 through the real routing path: a leg declared as TRANSFER, REFUND or INVOICE_PAYMENT is
   * refused by ALT_CLS_SourceLinkService before any read of a candidate and before any write, so a
   * transfer can never be routed as an allocation and a refund can never become a second
   * consumption expense. Routing a transfer or a refund is AXF-135's capability — this pass proves
   * the refusal, it does not add the routing.
   */
  @IsTest
  static void aTransferOrRefundRoleIsRefusedBeforeAnyWrite() {
    System.runAs(gestor()) {
      Account holder = holder('Titular Papel', 'AXF_Business');
      AXF_OBJ_BankAccountTransaction__c leg = movement(
        bank(holder.Id, 'r1').Id,
        'r1',
        500,
        'DEBIT'
      );
      ALT_CLS_SourceLinkService service = new ALT_CLS_SourceLinkService();
      Map<String, String> refusals = new Map<String, String>();
      Test.startTest();
      for (
        String role : new List<String>{
          ALT_CLS_SourceLinkService.ROLE_TRANSFER,
          ALT_CLS_SourceLinkService.ROLE_REFUND,
          ALT_CLS_SourceLinkService.ROLE_INVOICE_PAYMENT
        }
      ) {
        ALT_CLS_SourceLinkService.ConfirmInput input = new ALT_CLS_SourceLinkService.ConfirmInput();
        input.sourceId = leg.Id;
        input.sourceKind = 'BANK';
        input.sourceVersion = leg.AXF_BAT_NUM_Version__c;
        input.amount = 500;
        input.recognitionDate = Date.today();
        input.economicRole = role;
        input.operationKey = 'axf129-role-' + role;
        try {
          service.confirm(input);
          Assert.fail('Papel sem capacidade de roteamento: ' + role);
        } catch (ALT_CLS_SourceLinkService.SourceLinkException expected) {
          refusals.put(role, expected.getMessage());
        }
      }
      Test.stopTest();
      for (String role : refusals.keySet()) {
        Assert.areEqual(
          'UNSUPPORTED_ECONOMIC_ROLE',
          refusals.get(role),
          'AC-2: ' + role + ' e recusado antes de qualquer escrita.'
        );
      }
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_ReconciliationAllocation__c
        ],
        'AC-2: nenhum papel nao roteavel realiza escrita.'
      );
      Assert.areEqual(0, sets());
      Assert.areEqual(0, parcels());
      Assert.areEqual(0, questions());
    }
  }
}
