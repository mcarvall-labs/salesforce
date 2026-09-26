/**
 * @description Covers ALT_CLS_CashFlowHome (monthly movements, transaction search, settlement
 * and series creation) plus its thin entry points AXF_CLS_CTRL_RevenueHomeTable and the legacy
 * AXF_CLS_CashFlowHomeController.
 */
@IsTest
private class ALT_CLS_CashFlowHomeTest {
  @TestSetup
  static void setup() {
    User testUser = AXF_CLS_CashFlowTestFactory.createDomainUser();
    System.runAs(testUser) {
      Account holder = AXF_CLS_CashFlowTestFactory.createAccount('Home Holder');
      AXF_OBJ_Category__c salary = AXF_CLS_CashFlowTestFactory.createCategory(
        'Salario',
        false
      );
      AXF_CLS_CashFlowTestFactory.createCategory('Mercado', true);
      AXF_OBJ_BankAccount__c bank = AXF_CLS_CashFlowTestFactory.createBankAccount(
        holder.Id,
        'HOME_BANK',
        10
      );
      AXF_OBJ_CreditCard__c card = AXF_CLS_CashFlowTestFactory.createCreditCard(
        holder.Id,
        'HOME_CARD'
      );

      AXF_OBJ_CashFlow__c revenueWithCategory = AXF_CLS_CashFlowTestFactory.buildCashFlow(
        false,
        holder.Id,
        'Salario',
        5000,
        Date.today(),
        'PENDENTE'
      );
      revenueWithCategory.AXF_CF_LKP_Category__c = salary.Id;
      insert new List<AXF_OBJ_CashFlow__c>{
        revenueWithCategory,
        AXF_CLS_CashFlowTestFactory.buildCashFlow(
          false,
          holder.Id,
          'Freela',
          800,
          Date.today(),
          'PENDENTE'
        ),
        AXF_CLS_CashFlowTestFactory.buildCashFlow(
          false,
          holder.Id,
          'Mes seguinte',
          800,
          Date.today().toStartOfMonth().addMonths(1),
          'PENDENTE'
        ),
        AXF_CLS_CashFlowTestFactory.buildCashFlow(
          true,
          holder.Id,
          'Despesa',
          300,
          Date.today(),
          'PENDENTE'
        )
      };
      insert AXF_CLS_CashFlowTestFactory.buildBankTransaction(
        bank.Id,
        'HOME_BAT',
        5000,
        Date.today(),
        'Salario empresa'
      );
      insert AXF_CLS_CashFlowTestFactory.buildCardTransaction(
        card.Id,
        'HOME_CCT',
        50,
        Date.today(),
        'Estorno salario'
      );
    }
  }

  private static Id holderId() {
    return [SELECT Id FROM Account WHERE Name = 'Home Holder' LIMIT 1].Id;
  }

  private static ALT_CLS_CashFlowHome.CashFlowSeriesRequest request(
    String entryType,
    String paymentMode,
    Decimal amount,
    Integer installments
  ) {
    ALT_CLS_CashFlowHome.CashFlowSeriesRequest value = new ALT_CLS_CashFlowHome.CashFlowSeriesRequest();
    value.entryType = entryType;
    value.description = 'Serie ' + paymentMode;
    value.accountId = holderId();
    value.purchaseDate = Date.today();
    value.firstDueDate = Date.today().addDays(1);
    value.paymentMode = paymentMode;
    value.paymentMethod = 'BOLETO';
    value.amount = amount;
    value.totalInstallments = installments;
    return value;
  }

  private static String createError(
    ALT_CLS_CashFlowHome.CashFlowSeriesRequest value
  ) {
    try {
      new ALT_CLS_CashFlowHome().createCashFlowSeries(value);
      return null;
    } catch (IllegalArgumentException e) {
      return e.getMessage();
    }
  }

  @IsTest
  static void returnsMonthlyMovementsWithFilters() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Id salaryId = [SELECT Id FROM AXF_OBJ_Category__c WHERE Name = 'Salario']
      .Id;

      Test.startTest();
      List<AXF_OBJ_CashFlow__c> revenues = AXF_CLS_CTRL_RevenueHomeTable.getMonthlyMovements(
        'AXF_CF_RT_Revenue',
        null
      );
      List<AXF_OBJ_CashFlow__c> salaryOnly = AXF_CLS_CTRL_RevenueHomeTable.getMonthlyMovements(
        'AXF_CF_RT_Revenue',
        salaryId
      );
      List<AXF_OBJ_CashFlow__c> unknownType = AXF_CLS_CTRL_RevenueHomeTable.getMonthlyMovements(
        'Unknown_RT',
        null
      );
      List<AXF_OBJ_CashFlow__c> legacyRevenues = AXF_CLS_CashFlowHomeController.getMonthlyMovements(
        'AXF_CF_RT_Revenue',
        salaryId
      );
      List<AXF_OBJ_CashFlow__c> legacyUnknown = AXF_CLS_CashFlowHomeController.getMonthlyMovements(
        'Unknown_RT',
        null
      );
      List<AXF_OBJ_CashFlow__c> legacyAll = AXF_CLS_CashFlowHomeController.getMonthlyMovements(
        'AXF_CF_RT_Expense',
        null
      );
      Test.stopTest();

      Assert.areEqual(
        2,
        revenues.size(),
        'Only current-month revenues are returned'
      );
      Assert.areEqual(1, salaryOnly.size());
      Assert.areEqual('Salario', salaryOnly[0].Name);
      Assert.isTrue(unknownType.isEmpty());
      Assert.areEqual(1, legacyRevenues.size());
      Assert.isTrue(legacyUnknown.isEmpty());
      Assert.areEqual(1, legacyAll.size());
    }
  }

  @IsTest
  static void searchesTransactionsByDescription() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Test.startTest();
      List<AXF_OBJ_BankAccountTransaction__c> banks = AXF_CLS_CTRL_RevenueHomeTable.searchBankTransactions(
        'salario'
      );
      List<AXF_OBJ_CreditCardTransaction__c> cards = AXF_CLS_CTRL_RevenueHomeTable.searchCreditCardTransactions(
        'salario'
      );
      List<AXF_OBJ_BankAccountTransaction__c> noMatch = AXF_CLS_CTRL_RevenueHomeTable.searchBankTransactions(
        'inexistente'
      );
      List<AXF_OBJ_BankAccountTransaction__c> legacyBanks = AXF_CLS_CashFlowHomeController.searchBankTransactions(
        'Salario'
      );
      List<AXF_OBJ_CreditCardTransaction__c> legacyCards = AXF_CLS_CashFlowHomeController.searchCreditCardTransactions(
        'Estorno'
      );
      Test.stopTest();

      Assert.areEqual(1, banks.size());
      Assert.areEqual(5000, banks[0].AXF_BAT_CUR_Amount__c);
      Assert.areEqual(1, cards.size());
      Assert.isTrue(noMatch.isEmpty());
      Assert.areEqual(1, legacyBanks.size());
      Assert.areEqual(1, legacyCards.size());
    }
  }

  @IsTest
  static void settlesRevenueAndReportsFailures() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      AXF_OBJ_CashFlow__c freela = [
        SELECT Id
        FROM AXF_OBJ_CashFlow__c
        WHERE Name = 'Freela'
      ];
      AXF_OBJ_CashFlow__c salary = [
        SELECT Id
        FROM AXF_OBJ_CashFlow__c
        WHERE Name = 'Salario'
      ];
      AXF_OBJ_CashFlow__c expense = [
        SELECT Id
        FROM AXF_OBJ_CashFlow__c
        WHERE Name = 'Despesa'
      ];
      Id bankTxnId = [SELECT Id FROM AXF_OBJ_BankAccountTransaction__c LIMIT 1]
      .Id;
      Id cardTxnId = [SELECT Id FROM AXF_OBJ_CreditCardTransaction__c LIMIT 1]
      .Id;

      Test.startTest();
      AXF_CLS_CTRL_RevenueHomeTable.settleCashFlow(
        freela.Id,
        'RECEBIDA',
        Date.today(),
        null,
        null
      );
      String missingId;
      try {
        AXF_CLS_CTRL_RevenueHomeTable.settleCashFlow(
          null,
          'RECEBIDA',
          Date.today(),
          null,
          null
        );
      } catch (AuraHandledException e) {
        missingId = e.getMessage();
      }
      String linkFailure;
      try {
        // Linking without the reconciliation service violates the reconciliation invariant.
        AXF_CLS_CTRL_RevenueHomeTable.settleCashFlow(
          salary.Id,
          'RECEBIDA',
          Date.today(),
          bankTxnId,
          cardTxnId
        );
      } catch (AuraHandledException e) {
        linkFailure = e.getMessage();
      }
      String serviceNullId;
      try {
        new ALT_CLS_CashFlowHome()
          .settleCashFlow(null, 'PAGA', Date.today(), null, null);
      } catch (IllegalArgumentException e) {
        serviceNullId = e.getMessage();
      }
      AXF_CLS_CashFlowHomeController.settleCashFlow(
        expense.Id,
        'PAGA',
        Date.today(),
        null,
        null
      );
      Boolean legacyFailed = false;
      try {
        AXF_CLS_CashFlowHomeController.settleCashFlow(
          salary.Id,
          'RECEBIDA',
          Date.today(),
          bankTxnId,
          null
        );
      } catch (DmlException e) {
        legacyFailed = true;
      }
      Test.stopTest();

      Assert.areEqual(
        'RECEBIDA',
        [
          SELECT AXF_CF_PKL_Status__c
          FROM AXF_OBJ_CashFlow__c
          WHERE Id = :freela.Id
        ]
        .AXF_CF_PKL_Status__c
      );
      Assert.areEqual(
        'PAGA',
        [
          SELECT AXF_CF_PKL_Status__c
          FROM AXF_OBJ_CashFlow__c
          WHERE Id = :expense.Id
        ]
        .AXF_CF_PKL_Status__c
      );
      // AuraHandledException built without setMessage() exposes a generic message in tests.
      Assert.isNotNull(missingId, 'A null Cash Flow ID is rejected');
      Assert.isNotNull(
        linkFailure,
        'Invalid reconciliation links are rejected'
      );
      Assert.areEqual(
        'PENDENTE',
        [
          SELECT AXF_CF_PKL_Status__c
          FROM AXF_OBJ_CashFlow__c
          WHERE Id = :salary.Id
        ]
        .AXF_CF_PKL_Status__c,
        'Failed settlement leaves the entry untouched'
      );
      Assert.areEqual('Cash Flow ID is required.', serviceNullId);
      Assert.isTrue(legacyFailed, 'Legacy controller surfaces the DML failure');
    }
  }

  @IsTest
  static void createsSingleAndInstallmentEntries() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      ALT_CLS_CashFlowHome.CashFlowSeriesRequest paidRevenue = request(
        'RECEITA',
        'A_VISTA',
        250,
        null
      );
      paidRevenue.firstDueDate = Date.today().addDays(-3);
      paidRevenue.isPaid = true;
      paidRevenue.paidValue = 250;
      paidRevenue.paymentDate = Date.today();
      ALT_CLS_CashFlowHome.CashFlowSeriesRequest paidExpense = request(
        'DESPESA',
        'A_VISTA',
        80,
        1
      );
      paidExpense.isPaid = true;
      paidExpense.paidValue = 80;
      paidExpense.paymentDate = Date.today();
      ALT_CLS_CashFlowHome.CashFlowSeriesRequest overdueExpense = request(
        'Expense',
        'A_VISTA',
        30,
        1
      );
      overdueExpense.firstDueDate = Date.today().addDays(-10);
      ALT_CLS_CashFlowHome.CashFlowSeriesRequest installments = request(
        'DESPESA',
        'PARCELADO',
        100,
        3
      );
      installments.isTotalAmount = true;
      installments.firstDueDate = null;
      installments.purchaseDate = null;

      Test.startTest();
      ALT_CLS_CashFlowHome service = new ALT_CLS_CashFlowHome();
      Id revenueId = service.createCashFlowSeries(paidRevenue)[0];
      Id paidExpenseId = service.createCashFlowSeries(paidExpense)[0];
      Id overdueId = service.createCashFlowSeries(overdueExpense)[0];
      List<Id> installmentIds = service.createCashFlowSeries(installments);
      Test.stopTest();

      Assert.areEqual(
        'RECEBIDA_EM_ATRASO',
        [
          SELECT AXF_CF_PKL_Status__c
          FROM AXF_OBJ_CashFlow__c
          WHERE Id = :revenueId
        ]
        .AXF_CF_PKL_Status__c
      );
      Assert.areEqual(
        'PAGA',
        [
          SELECT AXF_CF_PKL_Status__c
          FROM AXF_OBJ_CashFlow__c
          WHERE Id = :paidExpenseId
        ]
        .AXF_CF_PKL_Status__c
      );
      Assert.areEqual(
        'VENCIDA',
        [
          SELECT AXF_CF_PKL_Status__c
          FROM AXF_OBJ_CashFlow__c
          WHERE Id = :overdueId
        ]
        .AXF_CF_PKL_Status__c
      );
      Assert.areEqual(3, installmentIds.size());
      List<AXF_OBJ_CashFlow__c> parts = [
        SELECT
          AXF_CF_CUR_Value__c,
          Name,
          AXF_CF_LKP_InstallmentGroup__r.AXF_IG_PKL_GroupType__c,
          AXF_CF_LKP_InstallmentGroup__r.AXF_IG_CUR_TotalAmount__c
        FROM AXF_OBJ_CashFlow__c
        WHERE Id IN :installmentIds
        ORDER BY AXF_CF_NUM_CurrentInstallment__c
      ];
      Assert.areEqual(33.33, parts[0].AXF_CF_CUR_Value__c);
      Assert.areEqual(
        33.34,
        parts[2].AXF_CF_CUR_Value__c,
        'Last installment absorbs rounding'
      );
      Assert.areEqual('Serie PARCELADO (1/3)', parts[0].Name);
      Assert.areEqual(
        'INSTALLMENT',
        parts[0].AXF_CF_LKP_InstallmentGroup__r.AXF_IG_PKL_GroupType__c
      );
      Assert.areEqual(
        100,
        parts[0].AXF_CF_LKP_InstallmentGroup__r.AXF_IG_CUR_TotalAmount__c
      );
    }
  }

  @IsTest
  static void createsRecurringFinancingAndConsortiumGroups() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      ALT_CLS_CashFlowHome.CashFlowSeriesRequest recurring = request(
        'DESPESA',
        'RECORRENTE',
        120,
        3
      );
      recurring.recurringType = 'VARIAVEL';
      recurring.provisioningStrategy = 'MEDIA_MOVEL';
      ALT_CLS_CashFlowHome.CashFlowSeriesRequest price = request(
        'DESPESA',
        'FINANCIAMENTO',
        500,
        10
      );
      price.financingType = 'PRICE';
      ALT_CLS_CashFlowHome.CashFlowSeriesRequest consortium = request(
        'DESPESA',
        'CONSORCIO',
        300,
        2
      );
      consortium.adjustmentAnniversary = Date.today().addYears(1);

      Test.startTest();
      ALT_CLS_CashFlowHome service = new ALT_CLS_CashFlowHome();
      List<Id> recurringIds = service.createCashFlowSeries(recurring);
      List<Id> priceIds = service.createCashFlowSeries(price);
      List<Id> consortiumIds = service.createCashFlowSeries(consortium);
      Test.stopTest();

      AXF_OBJ_CashFlow__c firstRecurring = [
        SELECT
          AXF_CF_NUM_TotalInstallments__c,
          AXF_CF_CHK_IsEstimated__c,
          AXF_CF_PKL_ProvisioningStrategy__c,
          AXF_CF_LKP_InstallmentGroup__r.AXF_IG_PKL_GroupType__c,
          AXF_CF_LKP_InstallmentGroup__r.AXF_IG_NUM_TotalInstallments__c
        FROM AXF_OBJ_CashFlow__c
        WHERE Id = :recurringIds[0]
      ];
      Assert.areEqual(3, recurringIds.size());
      Assert.isNull(firstRecurring.AXF_CF_NUM_TotalInstallments__c);
      Assert.isTrue(firstRecurring.AXF_CF_CHK_IsEstimated__c);
      Assert.areEqual(
        'MEDIA_MOVEL',
        firstRecurring.AXF_CF_PKL_ProvisioningStrategy__c
      );
      Assert.areEqual(
        'RECURRING',
        firstRecurring.AXF_CF_LKP_InstallmentGroup__r.AXF_IG_PKL_GroupType__c
      );
      Assert.isNull(
        firstRecurring.AXF_CF_LKP_InstallmentGroup__r.AXF_IG_NUM_TotalInstallments__c
      );

      Assert.areEqual(
        7,
        priceIds.size(),
        'PRICE financing only materializes the initial window'
      );
      AXF_OBJ_CashFlow__c firstPrice = [
        SELECT
          AXF_CF_LKP_InstallmentGroup__r.AXF_IG_PKL_FinancingType__c,
          AXF_CF_LKP_InstallmentGroup__r.AXF_IG_PCT_MonthlyAdjustmentRate__c
        FROM AXF_OBJ_CashFlow__c
        WHERE Id = :priceIds[0]
      ];
      Assert.areEqual(
        'PRICE',
        firstPrice.AXF_CF_LKP_InstallmentGroup__r.AXF_IG_PKL_FinancingType__c
      );
      Assert.isNull(
        firstPrice.AXF_CF_LKP_InstallmentGroup__r.AXF_IG_PCT_MonthlyAdjustmentRate__c
      );

      Assert.areEqual(2, consortiumIds.size());
      AXF_OBJ_CashFlow__c firstConsortium = [
        SELECT
          AXF_CF_LKP_InstallmentGroup__r.AXF_IG_PKL_GroupType__c,
          AXF_CF_LKP_InstallmentGroup__r.AXF_IG_DAT_AdjustmentAnniversary__c
        FROM AXF_OBJ_CashFlow__c
        WHERE Id = :consortiumIds[0]
      ];
      Assert.areEqual(
        'CONSORTIUM',
        firstConsortium.AXF_CF_LKP_InstallmentGroup__r.AXF_IG_PKL_GroupType__c
      );
      Assert.areEqual(
        Date.today().addYears(1),
        firstConsortium.AXF_CF_LKP_InstallmentGroup__r.AXF_IG_DAT_AdjustmentAnniversary__c
      );
    }
  }

  @IsTest
  static void createsSacFinancingWithDefaultAdjustmentRate() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      ALT_CLS_CashFlowHome.CashFlowSeriesRequest sac = request(
        'DESPESA',
        'FINANCIAMENTO_SAC',
        1000,
        3
      );

      Test.startTest();
      List<Id> ids = new ALT_CLS_CashFlowHome().createCashFlowSeries(sac);
      Test.stopTest();

      Assert.isFalse(ids.isEmpty());
      AXF_OBJ_InstallmentGroup__c groupRecord = [
        SELECT
          AXF_IG_PKL_GroupType__c,
          AXF_IG_PKL_FinancingType__c,
          AXF_IG_PCT_MonthlyAdjustmentRate__c
        FROM AXF_OBJ_InstallmentGroup__c
        WHERE
          Id IN (
            SELECT AXF_CF_LKP_InstallmentGroup__c
            FROM AXF_OBJ_CashFlow__c
            WHERE Id = :ids[0]
          )
      ];
      Assert.areEqual('FINANCING', groupRecord.AXF_IG_PKL_GroupType__c);
      Assert.areEqual('SAC', groupRecord.AXF_IG_PKL_FinancingType__c);
      Assert.areEqual(-1.5, groupRecord.AXF_IG_PCT_MonthlyAdjustmentRate__c);
    }
  }

  @IsTest
  static void rejectsInconsistentGroupConfiguration() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      ALT_CLS_CashFlowHome.CashFlowSeriesRequest badFinancingType = request(
        'DESPESA',
        'FINANCIAMENTO',
        100,
        2
      );
      badFinancingType.financingType = 'balloon';
      ALT_CLS_CashFlowHome.CashFlowSeriesRequest rateOnPrice = request(
        'DESPESA',
        'FINANCIAMENTO',
        100,
        2
      );
      rateOnPrice.financingType = 'PRICE';
      rateOnPrice.monthlyAdjustmentRate = 1;
      ALT_CLS_CashFlowHome.CashFlowSeriesRequest consortiumWithoutAnniversary = request(
        'DESPESA',
        'CONSORCIO',
        100,
        2
      );
      ALT_CLS_CashFlowHome.CashFlowSeriesRequest anniversaryOutsideConsortium = request(
        'DESPESA',
        'PARCELADO',
        100,
        2
      );
      anniversaryOutsideConsortium.adjustmentAnniversary = Date.today();

      Test.startTest();
      String financingError = createError(badFinancingType);
      String rateError = createError(rateOnPrice);
      String consortiumError = createError(consortiumWithoutAnniversary);
      String anniversaryError = createError(anniversaryOutsideConsortium);
      Test.stopTest();

      Assert.areEqual('Financing Type must be PRICE or SAC.', financingError);
      Assert.areEqual(
        'Monthly Adjustment Rate is applicable only to SAC financing groups.',
        rateError
      );
      Assert.areEqual(
        'Adjustment Anniversary is required for consortium groups.',
        consortiumError
      );
      Assert.areEqual(
        'Adjustment Anniversary is applicable only to consortium groups.',
        anniversaryError
      );
      Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_InstallmentGroup__c]);
    }
  }
}
