/**
 * @description Covers the bank account statement stack: ALT_CLS_BankAccountStatement,
 * AXF_CLS_CTRL_BankAccountStatement and the legacy AXF_CLS_BankAccountStatementController.
 */
@IsTest
private class AXF_CLS_BankAccountStatementTest {
  private static final String USER_KEY = 'bankstmt';

  @TestSetup
  static void setup() {
    AXF_CLS_AccountCardTestFactory.createUser(USER_KEY, false);
    Account holder = AXF_CLS_AccountCardTestFactory.newAccount(
      'Titular Extrato'
    );
    insert holder;
    AXF_OBJ_BankAccount__c bankAccount = AXF_CLS_AccountCardTestFactory.newBankAccount(
      'Conta',
      holder.Id,
      null,
      'BA-STMT-1'
    );
    insert bankAccount;
    AXF_OBJ_Category__c salary = AXF_CLS_AccountCardTestFactory.newCategory(
      'Salário',
      'AXF_CAT_RT_Revenue',
      null
    );
    insert salary;

    Date today = Date.today();
    insert new List<AXF_OBJ_BankAccountTransaction__c>{
      new AXF_OBJ_BankAccountTransaction__c(
        AXF_BAT_LKP_BankAccount__c = bankAccount.Id,
        AXF_BAT_EXI_PluggyTransactionId__c = 'BAT-1',
        AXF_BAT_DAT_Date__c = AXF_CLS_AccountCardTestFactory.middayOf(
          today.addDays(-10)
        ),
        AXF_BAT_TXT_Description__c = 'Salario Mensal',
        AXF_BAT_CUR_Amount__c = 1000,
        AXF_BAT_LKP_Category__c = salary.Id
      ),
      new AXF_OBJ_BankAccountTransaction__c(
        AXF_BAT_LKP_BankAccount__c = bankAccount.Id,
        AXF_BAT_EXI_PluggyTransactionId__c = 'BAT-2',
        AXF_BAT_DAT_Date__c = AXF_CLS_AccountCardTestFactory.middayOf(
          today.addDays(-5)
        ),
        AXF_BAT_TXT_Description__c = 'Mercado Central',
        AXF_BAT_CUR_Amount__c = -200
      ),
      new AXF_OBJ_BankAccountTransaction__c(
        AXF_BAT_LKP_BankAccount__c = bankAccount.Id,
        AXF_BAT_EXI_PluggyTransactionId__c = 'BAT-3',
        AXF_BAT_DAT_Date__c = AXF_CLS_AccountCardTestFactory.middayOf(
          today.addDays(-1)
        ),
        AXF_BAT_TXT_Description__c = 'Ajuste sem valor'
      )
    };
  }

  private static Id bankAccountId() {
    return [
      SELECT Id
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_EXI_PluggyAccountId__c = 'BA-STMT-1'
    ]
    .Id;
  }

  @IsTest
  static void serviceReturnsRunningBalanceAndTotals() {
    Id accountId = bankAccountId();
    ALT_CLS_BankAccountStatement.StatementResult result;
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      result = new ALT_CLS_BankAccountStatement()
        .getStatement(accountId, null, null, null, null, null);
      Test.stopTest();
    }

    Assert.areEqual(3, result.transactions.size());
    Assert.areEqual(1000, result.transactions[0].runningBalance);
    Assert.areEqual('Salário', result.transactions[0].categoryName);
    Assert.isTrue(result.transactions[0].isCredit);
    Assert.areEqual(800, result.transactions[1].runningBalance);
    Assert.isNull(result.transactions[1].categoryName);
    Assert.isFalse(result.transactions[1].isCredit);
    Assert.areEqual(
      0,
      result.transactions[2].amount,
      'Null amount must be treated as zero'
    );
    Assert.areEqual(1000, result.totalCredits);
    Assert.areEqual(-200, result.totalDebits);
    Assert.areEqual(800, result.netBalance);
    Assert.areEqual(
      'BRL',
      result.currencyIsoCode,
      'Defaults to BRL when the account has no currency set'
    );
  }

  @IsTest
  static void serviceReturnsAccountOwnCurrency() {
    Id accountId = bankAccountId();
    update new AXF_OBJ_BankAccount__c(
      Id = accountId,
      AXF_BA_PKL_Currency__c = 'USD'
    );
    ALT_CLS_BankAccountStatement.StatementResult result;
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      result = new ALT_CLS_BankAccountStatement()
        .getStatement(accountId, null, null, null, null, null);
      Test.stopTest();
    }

    Assert.areEqual(
      'USD',
      result.currencyIsoCode,
      'The statement must respect the currency configured on the bank account record'
    );
  }

  @IsTest
  static void serviceAppliesAllFilters() {
    Id accountId = bankAccountId();
    Date today = Date.today();
    ALT_CLS_BankAccountStatement service = new ALT_CLS_BankAccountStatement();
    ALT_CLS_BankAccountStatement.StatementResult byPeriod;
    ALT_CLS_BankAccountStatement.StatementResult byDescriptionAndValue;
    ALT_CLS_BankAccountStatement.StatementResult noAccount;
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      byPeriod = service.getStatement(
        accountId,
        today.addDays(-6),
        today,
        null,
        null,
        null
      );
      byDescriptionAndValue = service.getStatement(
        accountId,
        null,
        null,
        ' mercado ',
        -300,
        -100
      );
      noAccount = service.getStatement(null, today, today, 'x', 1, 2);
      Test.stopTest();
    }

    Assert.areEqual(
      2,
      byPeriod.transactions.size(),
      'Only the last two transactions are in the period'
    );
    Assert.areEqual(
      -200,
      byPeriod.transactions[0].runningBalance,
      'Running balance restarts on the filtered set'
    );
    Assert.areEqual(1, byDescriptionAndValue.transactions.size());
    Assert.areEqual(
      'Mercado Central',
      byDescriptionAndValue.transactions[0].description
    );
    Assert.areEqual(0, noAccount.transactions.size());
    Assert.areEqual(0, noAccount.netBalance);
  }

  @IsTest
  static void lwcControllerMapsServiceResult() {
    Id accountId = bankAccountId();
    AXF_CLS_CTRL_BankAccountStatement.StatementResult result;
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      result = AXF_CLS_CTRL_BankAccountStatement.getStatement(
        accountId,
        null,
        null,
        'Salario',
        0,
        null
      );
      Test.stopTest();
    }

    Assert.areEqual(1, result.transactions.size());
    AXF_CLS_CTRL_BankAccountStatement.TransactionRow row = result.transactions[0];
    Assert.areEqual('Salario Mensal', row.description);
    Assert.areEqual('Salário', row.categoryName);
    Assert.areEqual(1000, row.amount);
    Assert.areEqual(1000, row.runningBalance);
    Assert.isTrue(row.isCredit);
    Assert.isNotNull(row.id);
    Assert.isNotNull(row.transactionDate);
    Assert.areEqual(1000, result.totalCredits);
    Assert.areEqual(0, result.totalDebits);
    Assert.areEqual(1000, result.netBalance);
    Assert.areEqual('BRL', result.currencyIsoCode);
  }

  @IsTest
  static void legacyControllerComputesStatement() {
    Id accountId = bankAccountId();
    Date today = Date.today();
    AXF_CLS_BankAccountStatementController.StatementResult all;
    AXF_CLS_BankAccountStatementController.StatementResult filtered;
    AXF_CLS_BankAccountStatementController.StatementResult empty;
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      all = AXF_CLS_BankAccountStatementController.getStatement(
        accountId,
        null,
        null,
        null,
        null,
        null
      );
      filtered = AXF_CLS_BankAccountStatementController.getStatement(
        accountId,
        today.addDays(-30),
        today,
        'Mercado',
        -500,
        0
      );
      empty = AXF_CLS_BankAccountStatementController.getStatement(
        null,
        null,
        null,
        null,
        null,
        null
      );
      Test.stopTest();
    }

    Assert.areEqual(3, all.transactions.size());
    Assert.areEqual('Salário', all.transactions[0].categoryName);
    Assert.areEqual(800, all.transactions[2].runningBalance);
    Assert.areEqual(1000, all.totalCredits);
    Assert.areEqual(-200, all.totalDebits);
    Assert.areEqual(800, all.netBalance);
    Assert.areEqual(1, filtered.transactions.size());
    Assert.isFalse(filtered.transactions[0].isCredit);
    Assert.areEqual(0, empty.transactions.size());
  }
}
