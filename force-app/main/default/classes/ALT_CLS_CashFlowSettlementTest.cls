/**
 * @description Covers ALT_CLS_CashFlowSettlement (settlement, recurring forecast maintenance,
 * reconciliation suggestions and unreconcile) through its Aura entry point
 * AXF_CLS_CTRL_ExpenseHomeTable.
 */
@IsTest
private class ALT_CLS_CashFlowSettlementTest {
  @TestSetup
  static void setup() {
    User testUser = AXF_CLS_CashFlowTestFactory.createDomainUser();
    System.runAs(testUser) {
      Account holder = AXF_CLS_CashFlowTestFactory.createAccount(
        'Settlement Holder'
      );
      AXF_CLS_CashFlowTestFactory.createBankAccount(
        holder.Id,
        'SET_BANK_1',
        1000
      );
      AXF_CLS_CashFlowTestFactory.createBankAccount(holder.Id, 'SET_BANK_2', 0);
      AXF_CLS_CashFlowTestFactory.createCreditCard(holder.Id, 'SET_CARD_1');
      AXF_CLS_CashFlowTestFactory.createCreditCard(holder.Id, 'SET_CARD_2');
    }
  }

  private static Id holderId() {
    return [SELECT Id FROM Account WHERE Name = 'Settlement Holder' LIMIT 1].Id;
  }

  private static AXF_OBJ_BankAccount__c bank(String externalId) {
    return [
      SELECT Id
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_EXI_PluggyAccountId__c = :externalId
    ];
  }

  private static AXF_OBJ_CreditCard__c card(String externalId) {
    return [
      SELECT Id
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_EXI_PluggyCreditCardId__c = :externalId
    ];
  }

  private static AXF_OBJ_CashFlow__c insertExpense(
    Decimal value,
    Date dueDate,
    Id bankAccountId,
    Id creditCardId
  ) {
    AXF_OBJ_CashFlow__c entry = AXF_CLS_CashFlowTestFactory.buildCashFlow(
      true,
      holderId(),
      'Despesa',
      value,
      dueDate,
      'PENDENTE'
    );
    entry.AXF_CF_LKP_BankAccount__c = bankAccountId;
    entry.AXF_CF_LKP_CreditCard__c = creditCardId;
    insert entry;
    return entry;
  }

  private static String settleError(
    Id cashFlowId,
    Decimal paidValue,
    Date paymentDate,
    Id bankId,
    Id cardId
  ) {
    try {
      AXF_CLS_CTRL_ExpenseHomeTable.settleCashFlow(
        cashFlowId,
        paidValue,
        paymentDate,
        bankId,
        cardId,
        false
      );
      return null;
    } catch (AuraHandledException e) {
      return e.getMessage();
    }
  }

  /** Builds a recurring series: one settled entry (month -1), the target (today) and one open future entry. */
  private static List<AXF_OBJ_CashFlow__c> insertRecurringSeries(
    String recurringType,
    String strategy
  ) {
    AXF_OBJ_InstallmentGroup__c groupRecord = new AXF_OBJ_InstallmentGroup__c(
      AXF_IG_PKL_GroupType__c = 'RECURRING',
      AXF_IG_CUR_InstallmentAmount__c = 100,
      AXF_IG_DAT_FirstDueDate__c = Date.today().addMonths(-1)
    );
    insert groupRecord;
    List<AXF_OBJ_CashFlow__c> series = new List<AXF_OBJ_CashFlow__c>();
    for (Integer index = 0; index < 3; index++) {
      AXF_OBJ_CashFlow__c entry = AXF_CLS_CashFlowTestFactory.buildCashFlow(
        true,
        holderId(),
        'Conta de luz (' + (index + 1) + ')',
        100,
        Date.today().addMonths(index - 1),
        index == 0 ? 'PAGA' : 'PENDENTE'
      );
      entry.AXF_CF_PKL_PaymentMode__c = 'RECORRENTE';
      entry.AXF_CF_PKL_RecurringType__c = recurringType;
      entry.AXF_CF_PKL_ProvisioningStrategy__c = strategy;
      entry.AXF_CF_NUM_CurrentInstallment__c = index + 1;
      entry.AXF_CF_LKP_InstallmentGroup__c = groupRecord.Id;
      if (index == 0) {
        entry.AXF_CF_CUR_PaidValue__c = 90;
        entry.AXF_CF_DAT_PaymentDate__c = entry.AXF_CF_DAT_DueDate__c;
      }
      series.add(entry);
    }
    insert series;
    return series;
  }

  @IsTest
  static void settlesSingleExpenseWithBankReconciliation() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      AXF_OBJ_BankAccount__c bankAccount = bank('SET_BANK_1');
      AXF_OBJ_CashFlow__c entry = insertExpense(
        100,
        Date.today(),
        bankAccount.Id,
        null
      );
      AXF_OBJ_BankAccountTransaction__c txn = AXF_CLS_CashFlowTestFactory.buildBankTransaction(
        bankAccount.Id,
        'SET_BAT_1',
        -98,
        Date.today(),
        'Luz'
      );
      insert txn;

      Test.startTest();
      AXF_CLS_CTRL_ExpenseHomeTable.settleCashFlow(
        entry.Id,
        98,
        Date.today(),
        txn.Id,
        null,
        false
      );
      Test.stopTest();

      AXF_OBJ_CashFlow__c saved = [
        SELECT
          AXF_CF_PKL_Status__c,
          AXF_CF_CUR_Value__c,
          AXF_CF_CUR_PaidValue__c,
          AXF_CF_PKL_ReconciliationStatus__c,
          AXF_CF_LKP_BankAccountTransaction__c
        FROM AXF_OBJ_CashFlow__c
        WHERE Id = :entry.Id
      ];
      Assert.areEqual('PAGA', saved.AXF_CF_PKL_Status__c);
      Assert.areEqual(98, saved.AXF_CF_CUR_PaidValue__c);
      Assert.areEqual(98, saved.AXF_CF_CUR_Value__c);
      Assert.areEqual('RECONCILED', saved.AXF_CF_PKL_ReconciliationStatus__c);
      Assert.areEqual(txn.Id, saved.AXF_CF_LKP_BankAccountTransaction__c);
      AXF_OBJ_BankAccountTransaction__c savedTxn = [
        SELECT AXF_BAT_LKP_CashFlow__c, AXF_BAT_PKL_ReconciliationStatus__c
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE Id = :txn.Id
      ];
      Assert.areEqual(entry.Id, savedTxn.AXF_BAT_LKP_CashFlow__c);
      Assert.areEqual(
        'RECONCILED',
        savedTxn.AXF_BAT_PKL_ReconciliationStatus__c
      );
    }
  }

  @IsTest
  static void settlesLateExpenseWithCardReconciliationAndUnreconciles() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      AXF_OBJ_CreditCard__c creditCard = card('SET_CARD_1');
      AXF_OBJ_CashFlow__c entry = insertExpense(
        50,
        Date.today().addDays(-5),
        null,
        creditCard.Id
      );
      AXF_OBJ_CreditCardTransaction__c txn = AXF_CLS_CashFlowTestFactory.buildCardTransaction(
        creditCard.Id,
        'SET_CCT_1',
        50,
        Date.today(),
        'Farmacia'
      );
      insert txn;

      Test.startTest();
      AXF_CLS_CTRL_ExpenseHomeTable.settleCashFlow(
        entry.Id,
        50,
        Date.today(),
        null,
        txn.Id,
        false
      );
      AXF_OBJ_CashFlow__c settled = [
        SELECT AXF_CF_PKL_Status__c, AXF_CF_PKL_ReconciliationStatus__c
        FROM AXF_OBJ_CashFlow__c
        WHERE Id = :entry.Id
      ];
      AXF_CLS_CTRL_ExpenseHomeTable.unreconcile(entry.Id);
      Test.stopTest();

      Assert.areEqual('PAGA_EM_ATRASO', settled.AXF_CF_PKL_Status__c);
      Assert.areEqual('RECONCILED', settled.AXF_CF_PKL_ReconciliationStatus__c);
      AXF_OBJ_CashFlow__c saved = [
        SELECT
          AXF_CF_PKL_ReconciliationStatus__c,
          AXF_CF_LKP_CreditCardTransaction__c
        FROM AXF_OBJ_CashFlow__c
        WHERE Id = :entry.Id
      ];
      Assert.areEqual('UNRECONCILED', saved.AXF_CF_PKL_ReconciliationStatus__c);
      Assert.isNull(saved.AXF_CF_LKP_CreditCardTransaction__c);
      AXF_OBJ_CreditCardTransaction__c savedTxn = [
        SELECT AXF_CCT_LKP_CashFlow__c, AXF_CCT_PKL_ReconciliationStatus__c
        FROM AXF_OBJ_CreditCardTransaction__c
        WHERE Id = :txn.Id
      ];
      Assert.isNull(savedTxn.AXF_CCT_LKP_CashFlow__c);
      Assert.areEqual(
        'UNRECONCILED',
        savedTxn.AXF_CCT_PKL_ReconciliationStatus__c
      );
    }
  }

  @IsTest
  static void unreconcilesBankLinkAndHandlesFailures() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      AXF_OBJ_BankAccount__c bankAccount = bank('SET_BANK_1');
      AXF_OBJ_CashFlow__c entry = insertExpense(
        10,
        Date.today(),
        bankAccount.Id,
        null
      );
      AXF_OBJ_BankAccountTransaction__c txn = AXF_CLS_CashFlowTestFactory.buildBankTransaction(
        bankAccount.Id,
        'SET_BAT_U',
        -10,
        Date.today(),
        'x'
      );
      insert txn;
      AXF_OBJ_CashFlow__c unlinked = insertExpense(
        10,
        Date.today(),
        null,
        null
      );
      new ALT_CLS_CashFlowSettlement()
        .settleExpense(entry.Id, 10, Date.today(), txn.Id, null);

      Test.startTest();
      AXF_CLS_CTRL_ExpenseHomeTable.unreconcile(entry.Id);
      new ALT_CLS_CashFlowSettlement().unreconcile(unlinked.Id);
      String failure;
      try {
        AXF_CLS_CTRL_ExpenseHomeTable.unreconcile(null);
      } catch (AuraHandledException e) {
        failure = e.getMessage();
      }
      Test.stopTest();

      Assert.areEqual('Não foi possível desfazer a conciliação.', failure);
      Assert.areEqual(
        'UNRECONCILED',
        [
          SELECT AXF_BAT_PKL_ReconciliationStatus__c
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE Id = :txn.Id
        ]
        .AXF_BAT_PKL_ReconciliationStatus__c
      );
      Assert.isNull(
        [
          SELECT AXF_CF_LKP_BankAccountTransaction__c
          FROM AXF_OBJ_CashFlow__c
          WHERE Id = :entry.Id
        ]
        .AXF_CF_LKP_BankAccountTransaction__c
      );
      Assert.areEqual(
        'UNRECONCILED',
        [
          SELECT AXF_CF_PKL_ReconciliationStatus__c
          FROM AXF_OBJ_CashFlow__c
          WHERE Id = :unlinked.Id
        ]
        .AXF_CF_PKL_ReconciliationStatus__c
      );
    }
  }

  @IsTest
  static void rejectsInvalidSettlementRequests() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      AXF_OBJ_BankAccount__c bankOne = bank('SET_BANK_1');
      AXF_OBJ_BankAccount__c bankTwo = bank('SET_BANK_2');
      AXF_OBJ_CreditCard__c cardOne = card('SET_CARD_1');
      AXF_OBJ_CreditCard__c cardTwo = card('SET_CARD_2');
      AXF_OBJ_CashFlow__c bankEntry = insertExpense(
        10,
        Date.today(),
        bankOne.Id,
        null
      );
      AXF_OBJ_CashFlow__c cardEntry = insertExpense(
        10,
        Date.today(),
        null,
        cardOne.Id
      );
      AXF_OBJ_CashFlow__c revenue = AXF_CLS_CashFlowTestFactory.buildCashFlow(
        false,
        holderId(),
        'Receita',
        10,
        Date.today(),
        'PENDENTE'
      );
      insert revenue;
      AXF_OBJ_BankAccountTransaction__c foreignBankTxn = AXF_CLS_CashFlowTestFactory.buildBankTransaction(
        bankTwo.Id,
        'SET_BAT_F',
        -10,
        Date.today(),
        'f'
      );
      AXF_OBJ_BankAccountTransaction__c ownBankTxn = AXF_CLS_CashFlowTestFactory.buildBankTransaction(
        bankOne.Id,
        'SET_BAT_O',
        -10,
        Date.today(),
        'o'
      );
      insert new List<AXF_OBJ_BankAccountTransaction__c>{
        foreignBankTxn,
        ownBankTxn
      };
      AXF_OBJ_CreditCardTransaction__c foreignCardTxn = AXF_CLS_CashFlowTestFactory.buildCardTransaction(
        cardTwo.Id,
        'SET_CCT_F',
        10,
        Date.today(),
        'f'
      );
      AXF_OBJ_CreditCardTransaction__c ownCardTxn = AXF_CLS_CashFlowTestFactory.buildCardTransaction(
        cardOne.Id,
        'SET_CCT_O',
        10,
        Date.today(),
        'o'
      );
      insert new List<AXF_OBJ_CreditCardTransaction__c>{
        foreignCardTxn,
        ownCardTxn
      };

      // Reconcile the "own" transactions with other entries so they are already taken.
      AXF_OBJ_CashFlow__c bankOwner = insertExpense(
        10,
        Date.today(),
        bankOne.Id,
        null
      );
      AXF_OBJ_CashFlow__c cardOwner = insertExpense(
        10,
        Date.today(),
        null,
        cardOne.Id
      );
      ALT_CLS_CashFlowSettlement service = new ALT_CLS_CashFlowSettlement();
      service.settleExpense(
        bankOwner.Id,
        10,
        Date.today(),
        ownBankTxn.Id,
        null
      );
      service.settleExpense(
        cardOwner.Id,
        10,
        Date.today(),
        null,
        ownCardTxn.Id
      );

      Test.startTest();
      String missingValue = settleError(
        bankEntry.Id,
        null,
        Date.today(),
        null,
        null
      );
      String twoTransactions = settleError(
        bankEntry.Id,
        10,
        Date.today(),
        ownBankTxn.Id,
        ownCardTxn.Id
      );
      String notExpense = settleError(revenue.Id, 10, Date.today(), null, null);
      String bankTaken = settleError(
        bankEntry.Id,
        10,
        Date.today(),
        ownBankTxn.Id,
        null
      );
      String bankForeign = settleError(
        bankEntry.Id,
        10,
        Date.today(),
        foreignBankTxn.Id,
        null
      );
      String cardTaken = settleError(
        cardEntry.Id,
        10,
        Date.today(),
        null,
        ownCardTxn.Id
      );
      String cardForeign = settleError(
        cardEntry.Id,
        10,
        Date.today(),
        null,
        foreignCardTxn.Id
      );
      String relink = settleError(
        bankOwner.Id,
        10,
        Date.today(),
        foreignBankTxn.Id,
        null
      );
      String unexpected = settleError(
        (Id) (AXF_OBJ_CashFlow__c.SObjectType.getDescribe().getKeyPrefix() +
        '000000000000'),
        10,
        Date.today(),
        null,
        null
      );
      Test.stopTest();

      Assert.isTrue(missingValue.contains('positive Paid Value'), missingValue);
      Assert.isTrue(twoTransactions.contains('at most one'), twoTransactions);
      Assert.isTrue(notExpense.contains('Only Expense'), notExpense);
      Assert.isTrue(bankTaken.contains('already reconciled'), bankTaken);
      Assert.isTrue(bankForeign.contains('another Bank Account'), bankForeign);
      Assert.isTrue(cardTaken.contains('already reconciled'), cardTaken);
      Assert.isTrue(cardForeign.contains('another Credit Card'), cardForeign);
      Assert.isTrue(relink.contains('Unreconcile the existing'), relink);
      Assert.areEqual('Não foi possível liquidar o lançamento.', unexpected);
    }
  }

  @IsTest
  static void fixedRecurringSettlementExtendsForecastHorizon() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      List<AXF_OBJ_CashFlow__c> series = insertRecurringSeries('FIXO', null);

      Test.startTest();
      new ALT_CLS_CashFlowSettlement()
        .settleExpense(series[1].Id, 120, Date.today(), null, null);
      Test.stopTest();

      List<AXF_OBJ_CashFlow__c> future = [
        SELECT
          AXF_CF_CUR_Value__c,
          AXF_CF_NUM_CurrentInstallment__c,
          AXF_CF_CHK_IsEstimated__c
        FROM AXF_OBJ_CashFlow__c
        WHERE
          AXF_CF_LKP_InstallmentGroup__c = :series[0]
            .AXF_CF_LKP_InstallmentGroup__c
          AND AXF_CF_DAT_DueDate__c > TODAY
        ORDER BY AXF_CF_NUM_CurrentInstallment__c
      ];
      Assert.areEqual(
        6,
        future.size(),
        'Open-ended recurring series keeps six future occurrences'
      );
      for (AXF_OBJ_CashFlow__c entry : future) {
        Assert.areEqual(
          100,
          entry.AXF_CF_CUR_Value__c,
          'Fixed recurrence keeps the base amount'
        );
      }
      Assert.areEqual(
        8,
        future[future.size() - 1].AXF_CF_NUM_CurrentInstallment__c
      );
    }
  }

  @IsTest
  static void variableRecurringSettlementUsesMovingAverage() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      List<AXF_OBJ_CashFlow__c> series = insertRecurringSeries(
        'VARIAVEL',
        'MEDIA_MOVEL'
      );

      Test.startTest();
      new ALT_CLS_CashFlowSettlement()
        .settleExpense(series[1].Id, 110, Date.today(), null, null);
      Test.stopTest();

      AXF_OBJ_CashFlow__c nextEntry = [
        SELECT AXF_CF_CUR_Value__c, AXF_CF_CHK_IsEstimated__c
        FROM AXF_OBJ_CashFlow__c
        WHERE Id = :series[2].Id
      ];
      Assert.areEqual(
        100,
        nextEntry.AXF_CF_CUR_Value__c,
        'Average of 90 and 110'
      );
      Assert.isTrue(nextEntry.AXF_CF_CHK_IsEstimated__c);
      Assert.areEqual(
        6,
        [
          SELECT COUNT()
          FROM AXF_OBJ_CashFlow__c
          WHERE
            AXF_CF_LKP_InstallmentGroup__c = :series[0]
              .AXF_CF_LKP_InstallmentGroup__c
            AND AXF_CF_DAT_DueDate__c > TODAY
        ]
      );
    }
  }

  @IsTest
  static void variableRecurringSupportsLastAndBaseValueStrategies() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      List<AXF_OBJ_CashFlow__c> lastValue = insertRecurringSeries(
        'VARIAVEL',
        'ULTIMO_VALOR'
      );
      List<AXF_OBJ_CashFlow__c> baseValue = insertRecurringSeries(
        'VARIAVEL',
        'VALOR_BASE'
      );

      Test.startTest();
      ALT_CLS_CashFlowSettlement service = new ALT_CLS_CashFlowSettlement();
      service.settleExpense(lastValue[1].Id, 130, Date.today(), null, null);
      service.settleExpense(baseValue[1].Id, 130, Date.today(), null, null);
      Test.stopTest();

      Assert.areEqual(
        130,
        [
          SELECT AXF_CF_CUR_Value__c
          FROM AXF_OBJ_CashFlow__c
          WHERE Id = :lastValue[2].Id
        ]
        .AXF_CF_CUR_Value__c
      );
      Assert.areEqual(
        100,
        [
          SELECT AXF_CF_CUR_Value__c
          FROM AXF_OBJ_CashFlow__c
          WHERE Id = :baseValue[2].Id
        ]
        .AXF_CF_CUR_Value__c
      );
    }
  }

  @IsTest
  static void variableRecurringWithoutStrategyIsRejected() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      List<AXF_OBJ_CashFlow__c> series = insertRecurringSeries(
        'VARIAVEL',
        null
      );

      Test.startTest();
      String error = settleError(series[1].Id, 100, Date.today(), null, null);
      Test.stopTest();

      Assert.isTrue(error.contains('Unsupported Provisioning Strategy'), error);
    }
  }

  @IsTest
  static void suggestsMatchingTransactionsOrderedByScore() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      AXF_OBJ_BankAccount__c bankAccount = bank('SET_BANK_1');
      AXF_OBJ_CreditCard__c creditCard = card('SET_CARD_1');
      AXF_OBJ_CashFlow__c entry = insertExpense(
        100,
        Date.today(),
        bankAccount.Id,
        creditCard.Id
      );
      insert new List<AXF_OBJ_BankAccountTransaction__c>{
        AXF_CLS_CashFlowTestFactory.buildBankTransaction(
          bankAccount.Id,
          'SUG_B1',
          -100,
          Date.today(),
          'exact'
        ),
        AXF_CLS_CashFlowTestFactory.buildBankTransaction(
          bankAccount.Id,
          'SUG_B2',
          -103,
          Date.today().addDays(2),
          'close'
        ),
        AXF_CLS_CashFlowTestFactory.buildBankTransaction(
          bankAccount.Id,
          'SUG_B3',
          -150,
          Date.today().addDays(5),
          'far'
        )
      };
      insert new List<AXF_OBJ_CreditCardTransaction__c>{
        AXF_CLS_CashFlowTestFactory.buildCardTransaction(
          creditCard.Id,
          'SUG_C1',
          100,
          Date.today(),
          'card exact'
        ),
        AXF_CLS_CashFlowTestFactory.buildCardTransaction(
          creditCard.Id,
          'SUG_C2',
          100,
          Date.today().addDays(3),
          'card later'
        ),
        AXF_CLS_CashFlowTestFactory.buildCardTransaction(
          creditCard.Id,
          'SUG_C3',
          104,
          Date.today().addDays(-5),
          'card before'
        )
      };

      Test.startTest();
      List<AXF_CLS_CTRL_ExpenseHomeTable.ReconciliationSuggestionDTO> suggestions = AXF_CLS_CTRL_ExpenseHomeTable.getReconciliationSuggestions(
        entry.Id
      );
      String failure;
      try {
        AXF_CLS_CTRL_ExpenseHomeTable.getReconciliationSuggestions(null);
      } catch (AuraHandledException e) {
        failure = e.getMessage();
      }
      Test.stopTest();

      Assert.areEqual(
        5,
        suggestions.size(),
        'Low-score transaction is discarded'
      );
      Assert.areEqual(100, suggestions[0].score);
      Assert.areEqual(100, suggestions[1].score);
      Assert.areEqual('HIGH', suggestions[0].confidence);
      Assert.areEqual(90, suggestions[2].score);
      Assert.areEqual('card later', suggestions[2].description);
      Assert.areEqual('MEDIUM', suggestions[4].confidence);
      Assert.areEqual(
        'Não foi possível sugerir transações para conciliação.',
        failure
      );
    }
  }

  @IsTest
  static void delegatesQueriesToHomeService() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      AXF_OBJ_BankAccount__c bankAccount = bank('SET_BANK_1');
      AXF_OBJ_CreditCard__c creditCard = card('SET_CARD_1');
      insertExpense(40, Date.today(), null, null);
      insert AXF_CLS_CashFlowTestFactory.buildBankTransaction(
        bankAccount.Id,
        'DEL_B',
        -40,
        Date.today(),
        'Padaria central'
      );
      insert AXF_CLS_CashFlowTestFactory.buildCardTransaction(
        creditCard.Id,
        'DEL_C',
        40,
        Date.today(),
        'Padaria online'
      );

      Test.startTest();
      List<AXF_OBJ_CashFlow__c> movements = AXF_CLS_CTRL_ExpenseHomeTable.getMonthlyMovements(
        'AXF_CF_RT_Expense',
        null
      );
      List<AXF_OBJ_BankAccountTransaction__c> banks = AXF_CLS_CTRL_ExpenseHomeTable.searchBankTransactions(
        'Padaria'
      );
      List<AXF_OBJ_CreditCardTransaction__c> cards = AXF_CLS_CTRL_ExpenseHomeTable.searchCreditCardTransactions(
        'Padaria'
      );
      Test.stopTest();

      Assert.areEqual(1, movements.size());
      Assert.areEqual(1, banks.size());
      Assert.areEqual(1, cards.size());
    }
  }
}
