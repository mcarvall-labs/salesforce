@IsTest
private class AXF_CLS_CTRL_DashboardTest {
  private static final List<String> OBJECTS = new List<String>{
    'AXF_OBJ_Entry__c',
    'AXF_OBJ_BankAccount__c',
    'AXF_OBJ_CreditCard__c'
  };

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    User restricted = new User(
      Alias = 'AxfDash',
      Email = 'AxfDash@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'AxfDash',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profileId,
      TimeZoneSidKey = 'America/Sao_Paulo',
      Username = 'AxfDash' + System.currentTimeMillis() + '@example.com'
    );
    User withoutPermission = restricted.clone(false, true, false, false);
    withoutPermission.LastName = 'AxfDashNone';
    withoutPermission.Alias = 'AxfNone';
    withoutPermission.Username =
      'AxfDashNone' +
      System.currentTimeMillis() +
      '@example.com';
    insert new List<User>{ restricted, withoutPermission };
    ALT_CLS_SyncTestUser.create('axfdr', OBJECTS, restricted.Id);
    ALT_CLS_SyncTestUser.create('axfda', OBJECTS);
  }

  // Person Accounts take LastName instead of Name.
  private static Account holder(String name, String recordType) {
    Account account = new Account(
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get(recordType)
        .getRecordTypeId()
    );
    if (recordType == 'AXF_Person') {
      account.LastName = name;
    } else {
      account.Name = name;
    }
    insert account;
    return account;
  }

  private static AXF_OBJ_Entry__c entry(
    Id holderId,
    String type,
    String status,
    Date due,
    Decimal amount
  ) {
    AXF_OBJ_Entry__c entry = new AXF_OBJ_Entry__c(
      Name = 'Lançamento',
      AXF_ENT_MD_Holder__c = holderId,
      AXF_ENT_CUR_Amount__c = amount,
      AXF_ENT_DAT_DueDate__c = due,
      AXF_ENT_PKL_Type__c = type,
      AXF_ENT_PKL_Status__c = status
    );
    if (status == 'Realized') {
      entry.AXF_ENT_DAT_PaymentDate__c = due;
    }
    return entry;
  }

  private static ALT_CLS_Dashboard.Summary summary(Id holderId) {
    return AXF_CLS_CTRL_Dashboard.getSummary(holderId, Date.today());
  }

  // Overdue expense 40 (previous month), due-soon expense 100 and income 300 (today), realized
  // expense 20 (today), pending card purchase 60. Balance 1000 -> projected
  // 1000 + 300 - 100 - 40 = 1160; with the card 1100.
  private static Account scenario() {
    Account holder = holder('Titular', 'AXF_Business');
    insert new AXF_OBJ_BankAccount__c(
      Name = 'Conta',
      AXF_BA_MD_Holder__c = holder.Id,
      AXF_BA_PKL_Institution__c = '341',
      AXF_BA_PKL_Type__c = 'Checking',
      AXF_BA_CUR_Balance__c = 1000
    );
    AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
      Name = 'Cartão',
      AXF_CC_MD_Holder__c = holder.Id,
      AXF_CC_PKL_Institution__c = '341'
    );
    insert card;
    AXF_OBJ_Entry__c cardEntry = entry(
      holder.Id,
      'Expense',
      'Pending',
      Date.today(),
      60
    );
    cardEntry.AXF_ENT_LKP_CreditCard__c = card.Id;
    insert new List<AXF_OBJ_Entry__c>{
      entry(holder.Id, 'Expense', 'Pending', Date.today().addDays(-40), 40),
      entry(holder.Id, 'Expense', 'Pending', Date.today(), 100),
      entry(holder.Id, 'Income', 'Pending', Date.today(), 300),
      entry(holder.Id, 'Expense', 'Realized', Date.today(), 20),
      cardEntry
    };
    return holder;
  }

  @IsTest
  static void sumsIndicatorsAndBalances() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account holder = scenario();
      ALT_CLS_Dashboard.Summary result = summary(holder.Id);
      System.assertEquals(40, result.overdueExpense);
      System.assertEquals(1, result.overdueCount);
      System.assertEquals(100, result.dueSoonExpense);
      System.assertEquals(300, result.dueSoonIncome);
      System.assertEquals(2, result.dueSoonCount);
      System.assertEquals(300, result.income);
      System.assertEquals(120, result.expense, 'Pending 100 + realized 20');
      System.assertEquals(60, result.cardForecast);
      System.assertEquals(1000, result.currentBalance);
      System.assertEquals(1160, result.projectedBalance);
      System.assertEquals(1100, result.projectedBalanceWithCard);
      System.assertEquals(Date.today().toStartOfMonth(), result.monthStart);
    }
  }

  @IsTest
  static void convertsForeignCurrencyToBrl() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account holder = holder('Titular', 'AXF_Person');
      AXF_OBJ_Entry__c usd = entry(
        holder.Id,
        'Expense',
        'Pending',
        Date.today(),
        100
      );
      usd.put('CurrencyIsoCode', 'USD');
      insert usd;
      Decimal rate = [
        SELECT ConversionRate
        FROM CurrencyType
        WHERE IsoCode = 'USD'
      ]
      .ConversionRate;
      System.assertEquals(
        (100 / rate).setScale(2),
        summary(holder.Id).dueSoonExpense.setScale(2)
      );
    }
  }

  @IsTest
  static void allHoldersSumsEveryHolderAndFiltersAreIsolated() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account first = holder('Primeiro', 'AXF_Business');
      Account second = holder('Segundo', 'AXF_Person');
      insert new List<AXF_OBJ_Entry__c>{
        entry(first.Id, 'Expense', 'Pending', Date.today(), 10),
        entry(second.Id, 'Expense', 'Pending', Date.today(), 25)
      };
      System.assertEquals(10, summary(first.Id).dueSoonExpense);
      System.assertEquals(25, summary(second.Id).dueSoonExpense);
      System.assertEquals(35, summary(null).dueSoonExpense);
    }
  }

  @IsTest
  static void holdersListLeavesOutFamilyAndCustomer() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      holder('Pessoa', 'AXF_Person');
      holder('Empresa', 'AXF_Business');
      holder('Família', 'AXF_Family');
      holder('Cliente', 'AXF_Customer');
      Set<String> names = new Set<String>();
      for (
        ALT_CLS_Dashboard.Holder holder : AXF_CLS_CTRL_Dashboard.getHolders()
      ) {
        names.add(holder.name);
      }
      System.assert(names.contains('Pessoa'));
      System.assert(names.contains('Empresa'));
      System.assert(!names.contains('Família'));
      System.assert(!names.contains('Cliente'));
    }
  }

  @IsTest
  static void restrictedUserSumsOnlySharedHolders() {
    User restricted = [SELECT Id FROM User WHERE LastName = 'AxfDash'];
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account shared = holder('Dela', 'AXF_Person');
      Account hidden = holder('Do outro', 'AXF_Business');
      insert new List<AXF_OBJ_Entry__c>{
        entry(shared.Id, 'Expense', 'Pending', Date.today(), 10),
        entry(hidden.Id, 'Expense', 'Pending', Date.today(), 500)
      };
      insert new AccountShare(
        AccountId = shared.Id,
        UserOrGroupId = restricted.Id,
        AccountAccessLevel = 'Edit',
        OpportunityAccessLevel = 'None',
        CaseAccessLevel = 'None'
      );
    }
    System.runAs(restricted) {
      System.assertEquals(10, summary(null).dueSoonExpense);
      System.assertEquals(1, AXF_CLS_CTRL_Dashboard.getHolders().size());
    }
  }

  @IsTest
  static void userWithoutPermissionGetsAReadableError() {
    User none = [SELECT Id FROM User WHERE LastName = 'AxfDashNone'];
    System.runAs(none) {
      try {
        summary(null);
        System.assert(false, 'Should have been denied');
      } catch (AuraHandledException e) {
        System.assertNotEquals(null, e.getMessage());
      }
    }
  }
}
