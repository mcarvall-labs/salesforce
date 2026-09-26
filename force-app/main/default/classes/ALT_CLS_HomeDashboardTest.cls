/**
 * @description Axon Finance home dashboard over the production cash-flow model: month totals,
 * overdue lists, account balances, projected balance, the global holder filter and sanitized
 * controller errors.
 */
@IsTest
private class ALT_CLS_HomeDashboardTest {
  private static final Date TODAY = Date.today().toStartOfMonth().addDays(14);

  private static User reader() {
    return [SELECT Id FROM User WHERE Alias = 'axfhome' LIMIT 1];
  }

  private static Id cashFlowType(String developerName) {
    return AXF_OBJ_CashFlow__c.SObjectType.getDescribe()
      .getRecordTypeInfosByDeveloperName()
      .get(developerName)
      .getRecordTypeId();
  }

  private static AXF_OBJ_CashFlow__c entry(
    Id holderId,
    String recordType,
    Decimal value,
    Date dueDate,
    String status
  ) {
    return new AXF_OBJ_CashFlow__c(
      Name = recordType + ' ' + value,
      RecordTypeId = cashFlowType(recordType),
      AXF_CF_LKP_Account__c = holderId,
      AXF_CF_CUR_Value__c = value,
      AXF_CF_DAT_DueDate__c = dueDate,
      AXF_CF_PKL_Status__c = status
    );
  }

  @TestSetup
  static void setup() {
    User user = new User(
      Alias = 'axfhome',
      Email = 'axfhome@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Home Reader',
      LanguageLocaleKey = 'pt_BR',
      LocaleSidKey = 'pt_BR',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = [
        SELECT Id
        FROM Profile
        WHERE Name IN ('Standard User', 'Usuário Padrão')
        LIMIT 1
      ]
      .Id,
      Username = 'axfhome.' + System.now().getTime() + '@example.invalid'
    );
    insert user;
    insert new PermissionSetAssignment(
      AssigneeId = user.Id,
      PermissionSetId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'AXF_PS_User'
      ]
      .Id
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id business = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId();
      List<Account> holders = new List<Account>{
        new Account(Name = 'Michel Carvalho Lopes', RecordTypeId = business),
        new Account(Name = 'Gisele Lopes', RecordTypeId = business)
      };
      insert holders;
      AXF_OBJ_BankInstitution__c bank = new AXF_OBJ_BankInstitution__c(
        Name = 'Banco Home',
        AXF_BI_EXI_Bank_Number__c = '999'
      );
      insert bank;
      insert new List<AXF_OBJ_BankAccount__c>{
        new AXF_OBJ_BankAccount__c(
          AXF_BA_LKP_Account__c = holders[0].Id,
          AXF_BA_LKP_BankInstitution__c = bank.Id,
          AXF_BA_EXI_PluggyAccountId__c = 'home-ba-1',
          AXF_BA_CUR_Balance__c = 500
        ),
        new AXF_OBJ_BankAccount__c(
          AXF_BA_LKP_Account__c = holders[1].Id,
          AXF_BA_LKP_BankInstitution__c = bank.Id,
          AXF_BA_EXI_PluggyAccountId__c = 'home-ba-2',
          AXF_BA_CUR_Balance__c = 0
        )
      };
      Date month = TODAY.toStartOfMonth();
      insert new List<AXF_OBJ_CashFlow__c>{
        entry(
          holders[0].Id,
          'AXF_CF_RT_Revenue',
          1000,
          month.addDays(4),
          'RECEBIDA'
        ),
        entry(
          holders[0].Id,
          'AXF_CF_RT_Expense',
          300,
          month.addDays(9),
          'PENDENTE'
        ),
        entry(holders[1].Id, 'AXF_CF_RT_Expense', 50, month.addDays(2), 'PAGA'),
        entry(
          holders[0].Id,
          'AXF_CF_RT_Expense',
          84.9,
          month.addDays(-20),
          'VENCIDA'
        ),
        entry(
          holders[1].Id,
          'AXF_CF_RT_Revenue',
          20,
          month.addDays(-35),
          'PENDENTE'
        ),
        entry(
          holders[0].Id,
          'AXF_CF_RT_Expense',
          10,
          month.addDays(-10),
          'PAGA'
        )
      };
    }
  }

  private static Id holderId(String name) {
    return [SELECT Id FROM Account WHERE Name = :name LIMIT 1].Id;
  }

  @IsTest
  static void aggregatesEveryHolder() {
    ALT_CLS_HomeDashboard.todayOverride = TODAY;
    ALT_CLS_HomeDashboard.DashboardView view;
    System.runAs(reader()) {
      Test.startTest();
      view = AXF_CLS_CTRL_HomeDashboard.getDashboard(null);
      Test.stopTest();
    }
    Assert.areEqual(2, view.holders.size());
    Assert.areEqual(TODAY.toStartOfMonth(), view.monthStart);
    Assert.areEqual(1000, view.plannedRevenue);
    Assert.areEqual(1000, view.realizedRevenue);
    Assert.areEqual(350, view.plannedExpense);
    Assert.areEqual(50, view.realizedExpense);
    Assert.areEqual(650, view.plannedBalance);
    Assert.areEqual(950, view.realizedBalance);
    Assert.areEqual(1, view.monthRevenues.size());
    Assert.areEqual(2, view.monthExpenses.size());
    Assert.areEqual('SETTLED', view.monthRevenues[0].status);
    Assert.areEqual(1, view.overdueExpenses.size());
    Assert.areEqual(84.9, view.overdueExpenseTotal);
    Assert.areEqual(1, view.overdueRevenues.size());
    Assert.areEqual(20, view.overdueRevenueTotal);
    Assert.areEqual(1, view.accounts.size(), 'zero balances are not listed');
    Assert.areEqual(500, view.accountsBalance);
    Assert.areEqual(650, view.monthSurplus);
    Assert.areEqual(1150, view.projectedBalance);
    Assert.isFalse(view.truncated);
  }

  @IsTest
  static void holderFilterAppliesToEveryPanel() {
    ALT_CLS_HomeDashboard.todayOverride = TODAY;
    Id gisele = holderId('Gisele Lopes');
    ALT_CLS_HomeDashboard.DashboardView view;
    System.runAs(reader()) {
      Test.startTest();
      view = AXF_CLS_CTRL_HomeDashboard.getDashboard(gisele);
      Test.stopTest();
    }
    Assert.areEqual(gisele, view.holderId);
    Assert.areEqual(0, view.plannedRevenue);
    Assert.areEqual(50, view.plannedExpense);
    Assert.areEqual(0, view.overdueExpenses.size());
    Assert.areEqual(1, view.overdueRevenues.size());
    Assert.areEqual(0, view.accountsBalance);
    Assert.areEqual(-50, view.projectedBalance);
  }

  @IsTest
  static void rejectsUnknownHolders() {
    Id bankAccount = [SELECT Id FROM AXF_OBJ_BankAccount__c LIMIT 1].Id;
    Id unknown =
      Account.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA';
    System.runAs(reader()) {
      for (Id candidate : new List<Id>{ bankAccount, unknown }) {
        try {
          AXF_CLS_CTRL_HomeDashboard.getDashboard(candidate);
          Assert.fail('an unknown holder must be refused');
        } catch (AuraHandledException expected) {
          Assert.areEqual('INVALID_INPUT', expected.getMessage());
        }
      }
    }
  }

  @IsTest
  static void labelsHoldersByFirstAndLastName() {
    Assert.areEqual(
      'Michel Lopes',
      ALT_CLS_HomeDashboard.shortName(' Michel Carvalho Lopes ')
    );
    Assert.areEqual('Gisele', ALT_CLS_HomeDashboard.shortName('Gisele'));
    Assert.isNull(ALT_CLS_HomeDashboard.shortName(null));
  }
}
