/**
 * @description Home dashboard (production parity): month totals, overdue lists from previous
 * months, account balances, projected balance, the global holder filter and sanitized errors.
 */
@IsTest
private class ALT_CLS_HomeDashboardTest {
  private static final Date TODAY = Date.newInstance(2026, 9, 15);

  private static Account holder(String name) {
    return new Account(
      Name = name,
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
  }

  private static AXF_OBJ_FinancialTransaction__c entry(
    Id holderId,
    String direction,
    Decimal amount,
    Date dueDate,
    String key
  ) {
    return new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = holderId,
      AXF_FTX_NUM_Magnitude__c = amount,
      AXF_FTX_PKL_Direction__c = direction,
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = dueDate,
      AXF_FTX_DAT_DueDate__c = dueDate,
      AXF_FTX_TXT_Description__c = 'Entry ' + key,
      AXF_FTX_TXT_UserCategory__c = 'Categoria ' + key,
      AXF_FTX_PKL_PlanKind__c = 'PLANNED',
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_NUM_Version__c = 0,
      AXF_FTX_EXI_ClientRequestId__c = 'home-' + key
    );
  }

  @TestSetup
  static void setup() {
    List<Account> holders = new List<Account>{
      holder('Michel Home'),
      holder('Gisele Home')
    };
    insert holders;
    insert new List<AXF_OBJ_FinancialTransaction__c>{
      entry(holders[0].Id, 'CREDIT', 1000, TODAY.addDays(5), 'rev'),
      entry(holders[0].Id, 'DEBIT', 300, TODAY.addDays(-3), 'exp'),
      entry(holders[1].Id, 'DEBIT', 50, TODAY, 'exp2'),
      entry(holders[0].Id, 'DEBIT', 84.9, TODAY.addMonths(-2), 'late'),
      entry(holders[1].Id, 'CREDIT', 20, TODAY.addMonths(-1), 'laterev'),
      entry(holders[0].Id, 'DEBIT', 999, TODAY.addMonths(-14), 'ancient')
    };
    insert new List<AXF_OBJ_BankAccount__c>{
      new AXF_OBJ_BankAccount__c(
        AXF_BA_LKP_Account__c = holders[0].Id,
        AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
        AXF_BA_CUR_CurrentBalance__c = 500,
        AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_BA_EXI_ManualKey__c = 'home-ba-1'
      ),
      new AXF_OBJ_BankAccount__c(
        AXF_BA_LKP_Account__c = holders[1].Id,
        AXF_BA_PKL_AvailabilityState__c = 'CUSTODY',
        AXF_BA_CUR_CurrentBalance__c = 7000,
        AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_BA_EXI_ManualKey__c = 'home-ba-2'
      )
    };
  }

  private static Id holderId(String name) {
    return [SELECT Id FROM Account WHERE Name = :name LIMIT 1].Id;
  }

  @IsTest
  static void aggregatesEveryAuthorizedHolder() {
    ALT_CLS_HomeDashboard.todayOverride = TODAY;
    Test.startTest();
    ALT_CLS_HomeDashboard.DashboardView view = AXF_CLS_CTRL_HomeDashboard.getDashboard(
      null
    );
    Test.stopTest();
    Assert.areEqual(2, view.holders.size());
    Assert.areEqual(Date.newInstance(2026, 9, 1), view.monthStart);
    Assert.areEqual(1000, view.plannedRevenue);
    Assert.areEqual(350, view.plannedExpense);
    Assert.areEqual(0, view.realizedRevenue);
    Assert.areEqual(650, view.plannedBalance);
    Assert.areEqual(0, view.realizedBalance);
    Assert.areEqual(1, view.monthRevenues.size());
    Assert.areEqual(2, view.monthExpenses.size());
    Assert.areEqual('Categoria exp', view.monthExpenses[0].category);
    Assert.areEqual('OPEN', view.monthExpenses[0].status);
    // Overdue only looks back OVERDUE_MONTHS; the 14-month-old entry is out of the window.
    Assert.areEqual(1, view.overdueExpenses.size());
    Assert.areEqual(84.9, view.overdueExpenseTotal);
    Assert.areEqual(1, view.overdueRevenues.size());
    Assert.areEqual(20, view.overdueRevenueTotal);
    // Accounts in custody are not available and stay out of the balance.
    Assert.areEqual(1, view.accounts.size());
    Assert.areEqual(500, view.accountsBalance);
    Assert.areEqual(650, view.monthSurplus);
    Assert.areEqual(1150, view.projectedBalance);
    Assert.areEqual('BRL', view.currencyIso);
    Assert.isFalse(view.mixedCurrency);
    Assert.isFalse(view.truncated);
  }

  @IsTest
  static void holderFilterAppliesToEveryPanel() {
    ALT_CLS_HomeDashboard.todayOverride = TODAY;
    Id gisele = holderId('Gisele Home');
    Test.startTest();
    ALT_CLS_HomeDashboard.DashboardView view = AXF_CLS_CTRL_HomeDashboard.getDashboard(
      gisele
    );
    Test.stopTest();
    Assert.areEqual(gisele, view.holderId);
    Assert.areEqual(0, view.plannedRevenue);
    Assert.areEqual(50, view.plannedExpense);
    Assert.areEqual(0, view.overdueExpenses.size());
    Assert.areEqual(1, view.overdueRevenues.size());
    Assert.areEqual(0, view.accounts.size());
    Assert.areEqual(-50, view.projectedBalance);
    Assert.areEqual('Gisele Home', view.monthExpenses[0].holderLabel);
  }

  @IsTest
  static void rejectsHoldersOutsideTheAuthorizedContext() {
    Id foreign = [SELECT Id FROM AXF_OBJ_BankAccount__c LIMIT 1].Id;
    Id unknownAccount =
      Account.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA';
    for (Id candidate : new List<Id>{ foreign, unknownAccount }) {
      try {
        AXF_CLS_CTRL_HomeDashboard.getDashboard(candidate);
        Assert.fail('holder outside the authorized context must be refused');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', expected.getMessage());
      }
    }
  }

  @IsTest
  static void emptyContextReturnsAnEmptyDashboard() {
    delete [SELECT Id FROM AXF_OBJ_BankAccount__c];
    delete [SELECT Id FROM AXF_OBJ_FinancialTransaction__c];
    delete [SELECT Id FROM Account];
    ALT_CLS_HomeDashboard.DashboardView view = new ALT_CLS_HomeDashboard()
      .dashboard(null);
    Assert.areEqual(0, view.holders.size());
    Assert.areEqual(0, view.projectedBalance);
    Assert.areEqual(0, view.monthExpenses.size());
  }
}
