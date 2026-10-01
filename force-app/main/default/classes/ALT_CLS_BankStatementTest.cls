@IsTest
private class ALT_CLS_BankStatementTest {
  @TestSetup
  static void setup() {
    ALT_CLS_SyncTestUser.create(
      'axfst',
      new List<String>{
        'AXF_OBJ_BankAccount__c',
        'AXF_OBJ_BankAccountTransaction__c'
      }
    );
  }

  private static Id accountWithTransactions() {
    Account holder = new Account(Name = 'Holder');
    insert holder;
    AXF_OBJ_BankAccount__c account = new AXF_OBJ_BankAccount__c(
      Name = 'Conta',
      AXF_BA_MD_Holder__c = holder.Id,
      AXF_BA_PKL_Institution__c = '341',
      AXF_BA_PKL_Type__c = 'Checking',
      AXF_BA_CUR_Balance__c = 1000
    );
    insert account;
    insert new List<AXF_OBJ_BankAccountTransaction__c>{
      tx(account.Id, Date.newInstance(2026, 9, 5), -100),
      tx(account.Id, Date.newInstance(2026, 9, 20), 50),
      tx(account.Id, Date.newInstance(2026, 10, 2), -200)
    };
    return account.Id;
  }

  private static AXF_OBJ_BankAccountTransaction__c tx(
    Id accountId,
    Date txDate,
    Decimal amount
  ) {
    return new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MD_BankAccount__c = accountId,
      AXF_BAT_DAT_Date__c = txDate,
      AXF_BAT_TXT_Description__c = 'Tx ' + txDate,
      AXF_BAT_CUR_Amount__c = amount
    );
  }

  @IsTest
  static void latestMonthIsDefaultAndRunningBalanceIsDerived() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      ALT_CLS_BankStatement.Statement s = new ALT_CLS_BankStatement()
        .build(accountWithTransactions(), null);
      System.assertEquals('2026-10', s.month);
      System.assertEquals(new List<String>{ '2026-10', '2026-09' }, s.months);
      System.assertEquals(1, s.rows.size());
      System.assertEquals(1000, s.rows[0].runningBalance);
    }
  }

  @IsTest
  static void olderMonthHasBalancesBeforeNewerTransactions() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      ALT_CLS_BankStatement.Statement s = new ALT_CLS_BankStatement()
        .build(accountWithTransactions(), '2026-09');
      System.assertEquals(2, s.rows.size());
      System.assertEquals(
        Date.newInstance(2026, 9, 20),
        s.rows[0].transactionDate
      );
      System.assertEquals(1200, s.rows[0].runningBalance);
      System.assertEquals(1150, s.rows[1].runningBalance);
      System.assertEquals(1000, s.balance);
    }
  }

  @IsTest
  static void accountWithoutTransactionsHasEmptyStatement() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account holder = new Account(Name = 'Empty');
      insert holder;
      AXF_OBJ_BankAccount__c account = new AXF_OBJ_BankAccount__c(
        Name = 'Vazia',
        AXF_BA_MD_Holder__c = holder.Id,
        AXF_BA_PKL_Institution__c = '341',
        AXF_BA_PKL_Type__c = 'Checking'
      );
      insert account;
      ALT_CLS_BankStatement.Statement s = new ALT_CLS_BankStatement()
        .build(account.Id, null);
      System.assertEquals(0, s.rows.size());
      System.assertEquals(0, s.months.size());
    }
  }

  @IsTest
  static void controllerReturnsViewAndRejectsMissingAccount() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_CLS_CTRL_BankStatement.StatementView view = AXF_CLS_CTRL_BankStatement.getStatement(
        accountWithTransactions(),
        '2026-09'
      );
      System.assertEquals(2, view.rows.size());
      System.assertEquals(1000, view.balance);
      try {
        AXF_CLS_CTRL_BankStatement.getStatement(null, null);
        System.assert(false, 'Expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assertNotEquals(null, e.getMessage());
      }
    }
  }

  @IsTest
  static void unknownMonthIsEmptyAndLimitFlagsTruncation() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id accountId = accountWithTransactions();
      System.assertEquals(
        0,
        new ALT_CLS_BankStatement().build(accountId, '2020-01').rows.size()
      );
      ALT_CLS_BankStatement.maxTransactions = 2;
      ALT_CLS_BankStatement.Statement s = new ALT_CLS_BankStatement()
        .build(accountId, null);
      System.assertEquals(true, s.truncated);
      System.assertEquals(new List<String>{ '2026-10', '2026-09' }, s.months);
    }
  }

  @IsTest
  static void sameDayTransactionsKeepACoherentRunningBalance() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id accountId = accountWithTransactions();
      insert new List<AXF_OBJ_BankAccountTransaction__c>{
        tx(accountId, Date.newInstance(2026, 10, 2), -10),
        tx(accountId, Date.newInstance(2026, 10, 2), -20)
      };
      List<ALT_CLS_BankStatement.Row> rows = new ALT_CLS_BankStatement()
        .build(accountId, '2026-10')
        .rows;
      System.assertEquals(3, rows.size());
      Decimal expected = 1000;
      for (ALT_CLS_BankStatement.Row row : rows) {
        System.assertEquals(expected, row.runningBalance);
        expected -= row.amount;
      }
    }
  }

  @IsTest
  static void controllerWrapsUnreadableAccount() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id accountId = accountWithTransactions();
      delete [SELECT Id FROM AXF_OBJ_BankAccount__c WHERE Id = :accountId];
      try {
        AXF_CLS_CTRL_BankStatement.getStatement(accountId, null);
        System.assert(false, 'Expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assertNotEquals(null, e.getMessage());
      }
    }
  }
}
