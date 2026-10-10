@IsTest
private class AXF_CLS_CTRL_DashboardPreviewTest {
  private static final List<String> OBJECTS = new List<String>{
    'AXF_OBJ_Entry__c',
    'AXF_OBJ_BankAccount__c',
    'AXF_OBJ_BankAccountTransaction__c',
    'AXF_OBJ_CreditCard__c',
    'AXF_OBJ_CreditCardTransaction__c',
    'AXF_OBJ_CreditCardInvoice__c'
  };

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    User restricted = new User(
      Alias = 'AxfPrv',
      Email = 'AxfPrv@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'AxfPrv',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profileId,
      TimeZoneSidKey = 'America/Sao_Paulo',
      Username = 'AxfPrv' + System.currentTimeMillis() + '@example.com'
    );
    User none = restricted.clone(false, true, false, false);
    none.LastName = 'AxfPrvNone';
    none.Alias = 'AxfPrvN';
    none.Username = 'AxfPrvNone' + System.currentTimeMillis() + '@example.com';
    insert new List<User>{ restricted, none };
    ALT_CLS_SyncTestUser.create('axfpr', OBJECTS, restricted.Id);
    ALT_CLS_SyncTestUser.create('axfpa', OBJECTS);
  }

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

  private static AXF_OBJ_BankAccount__c account(Id holderId, Decimal balance) {
    AXF_OBJ_BankAccount__c account = new AXF_OBJ_BankAccount__c(
      Name = 'Conta ' + balance,
      AXF_BA_MD_Holder__c = holderId,
      AXF_BA_PKL_Institution__c = '341',
      AXF_BA_PKL_Type__c = 'Checking',
      AXF_BA_CUR_Balance__c = balance
    );
    insert account;
    return account;
  }

  private static AXF_OBJ_BankAccountTransaction__c bank(
    Id accountId,
    Date day,
    Decimal amount,
    String status
  ) {
    AXF_OBJ_BankAccountTransaction__c bank = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MD_BankAccount__c = accountId,
      AXF_BAT_DAT_Date__c = day,
      AXF_BAT_CUR_Amount__c = amount,
      AXF_BAT_TXT_Description__c = 'Tx ' + amount,
      AXF_BAT_PKL_ReconciliationStatus__c = status
    );
    return bank;
  }

  @IsTest
  static void countsOpenTransactionsAndReturnsTheThreeMostRecent() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account holder = holder('Titular', 'AXF_Business');
      AXF_OBJ_BankAccount__c account = account(holder.Id, 100);
      Date start = Date.today().toStartOfMonth();
      AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
        Name = 'Cartão',
        AXF_CC_MD_Holder__c = holder.Id,
        AXF_CC_PKL_Institution__c = '341'
      );
      insert card;
      insert new List<AXF_OBJ_BankAccountTransaction__c>{
        bank(account.Id, start.addDays(1), -10, null),
        bank(account.Id, start.addDays(2), -20, 'Pending'),
        bank(account.Id, start.addDays(3), -30, null),
        bank(account.Id, start.addDays(4), -40, 'Reconciled'),
        bank(account.Id, start.addMonths(-1), -50, null)
      };
      insert new AXF_OBJ_CreditCardTransaction__c(
        AXF_CCT_MD_CreditCard__c = card.Id,
        AXF_CCT_DAT_Date__c = start.addDays(5),
        AXF_CCT_CUR_Amount__c = -60,
        AXF_CCT_TXT_Description__c = 'Compra',
        AXF_CCT_PKL_ReconciliationStatus__c = null
      );
      ALT_CLS_DashboardPreview.Pending result = AXF_CLS_CTRL_Dashboard.getPending(
        holder.Id,
        Date.today()
      );
      System.assertEquals(
        4,
        result.total,
        '3 bank + 1 card, in the month, not reconciled'
      );
      System.assertEquals(3, result.items.size());
      System.assertEquals('Compra', result.items[0].description);
      System.assertEquals('card', result.items[0].source);
      System.assertEquals(-30, result.items[1].amount);
      System.assertEquals(start.addDays(2), result.items[2].transactionDate);
    }
  }

  @IsTest
  static void excludesTransactionsAlreadyLinkedToAnEntry() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account holder = holder('Titular', 'AXF_Business');
      AXF_OBJ_BankAccount__c account = account(holder.Id, 100);
      Date start = Date.today().toStartOfMonth();
      AXF_OBJ_BankAccountTransaction__c linked = bank(
        account.Id,
        start,
        -10,
        null
      );
      AXF_OBJ_BankAccountTransaction__c open = bank(
        account.Id,
        start.addDays(1),
        -20,
        null
      );
      insert new List<AXF_OBJ_BankAccountTransaction__c>{ linked, open };
      insert new AXF_OBJ_Entry__c(
        Name = 'Ligado',
        AXF_ENT_MD_Holder__c = holder.Id,
        AXF_ENT_CUR_Amount__c = 10,
        AXF_ENT_DAT_DueDate__c = start,
        AXF_ENT_PKL_Type__c = 'Expense',
        AXF_ENT_PKL_Status__c = 'Pending',
        AXF_ENT_LKP_BankAccountTransaction__c = linked.Id
      );
      ALT_CLS_DashboardPreview.Pending result = AXF_CLS_CTRL_Dashboard.getPending(
        holder.Id,
        Date.today()
      );
      System.assertEquals(1, result.total);
      System.assertEquals(open.Id, result.items[0].id);
    }
  }

  @IsTest
  static void flagsTransactionsThatHaveASuggestedEntry() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account holder = holder('Titular', 'AXF_Business');
      AXF_OBJ_BankAccount__c account = account(holder.Id, 100);
      Date start = Date.today().toStartOfMonth();
      AXF_OBJ_BankAccountTransaction__c matching = bank(
        account.Id,
        start.addDays(2),
        -100,
        null
      );
      AXF_OBJ_BankAccountTransaction__c other = bank(
        account.Id,
        start.addDays(1),
        -7,
        null
      );
      insert new List<AXF_OBJ_BankAccountTransaction__c>{ matching, other };
      AXF_OBJ_Entry__c entry = new AXF_OBJ_Entry__c(
        Name = 'Conta de luz',
        AXF_ENT_MD_Holder__c = holder.Id,
        AXF_ENT_CUR_Amount__c = 100,
        AXF_ENT_DAT_DueDate__c = start.addDays(2),
        AXF_ENT_PKL_Type__c = 'Expense',
        AXF_ENT_PKL_Status__c = 'Pending',
        AXF_ENT_LKP_BankAccount__c = account.Id
      );
      insert entry;
      for (Id scope : new List<Id>{ holder.Id, null }) {
        ALT_CLS_DashboardPreview.Pending result = AXF_CLS_CTRL_Dashboard.getPending(
          scope,
          Date.today()
        );
        System.assertEquals(2, result.total);
        System.assertEquals(1, result.suggestions);
        System.assertEquals(matching.Id, result.items[0].id);
        System.assert(result.items[0].suggested);
        System.assert(!result.items[1].suggested);
      }
    }
  }

  @IsTest
  static void listsAccountBalancesAndCardAvailableLimits() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account first = holder('Primeiro', 'AXF_Business');
      Account second = holder('Segundo', 'AXF_Person');
      account(first.Id, 250);
      account(second.Id, 40);
      insert new AXF_OBJ_CreditCard__c(
        Name = 'Cartão A',
        AXF_CC_MD_Holder__c = first.Id,
        AXF_CC_PKL_Institution__c = '341',
        AXF_CC_CUR_Limit__c = 5000,
        AXF_CC_CUR_AvailableLimit__c = 3200
      );
      ALT_CLS_DashboardPreview.Sources one = AXF_CLS_CTRL_Dashboard.getSources(
        first.Id
      );
      System.assertEquals(1, one.accounts.size());
      System.assertEquals(250, one.accounts[0].value);
      System.assertEquals('Primeiro', one.accounts[0].holderName);
      System.assertEquals(1, one.cards.size());
      System.assertEquals(3200, one.cards[0].value);
      System.assertEquals(5000, one.cards[0].limitTotal);
      ALT_CLS_DashboardPreview.Sources all = AXF_CLS_CTRL_Dashboard.getSources(
        null
      );
      System.assertEquals(2, all.accounts.size());
      System.assertEquals(1, all.cards.size());
    }
  }

  @IsTest
  static void convertsForeignBalancesAndTransactions() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account holder = holder('Titular', 'AXF_Business');
      AXF_OBJ_BankAccount__c usd = new AXF_OBJ_BankAccount__c(
        Name = 'Conta USD',
        AXF_BA_MD_Holder__c = holder.Id,
        AXF_BA_PKL_Institution__c = '341',
        AXF_BA_PKL_Type__c = 'Checking',
        AXF_BA_CUR_Balance__c = 100
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
        AXF_CLS_CTRL_Dashboard.getSources(holder.Id)
          .accounts[0]
          .value.setScale(2)
      );
    }
  }

  @IsTest
  static void restrictedUserSeesOnlySharedHolders() {
    User restricted = [SELECT Id FROM User WHERE LastName = 'AxfPrv'];
    Date start = Date.today().toStartOfMonth();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account shared = holder('Dela', 'AXF_Person');
      Account hidden = holder('Do outro', 'AXF_Business');
      AXF_OBJ_BankAccount__c mine = account(shared.Id, 10);
      AXF_OBJ_BankAccount__c theirs = account(hidden.Id, 999);
      insert new List<AXF_OBJ_BankAccountTransaction__c>{
        bank(mine.Id, start, -1, null),
        bank(theirs.Id, start, -2, null)
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
      System.assertEquals(
        1,
        AXF_CLS_CTRL_Dashboard.getPending(null, Date.today()).total
      );
      ALT_CLS_DashboardPreview.Sources sources = AXF_CLS_CTRL_Dashboard.getSources(
        null
      );
      System.assertEquals(1, sources.accounts.size());
      System.assertEquals(10, sources.accounts[0].value);
    }
  }

  @IsTest
  static void userWithoutPermissionGetsAReadableError() {
    User none = [SELECT Id FROM User WHERE LastName = 'AxfPrvNone'];
    System.runAs(none) {
      try {
        AXF_CLS_CTRL_Dashboard.getSources(null);
        System.assert(false, 'Should have been denied');
      } catch (AuraHandledException e) {
        System.assertNotEquals('Script-thrown exception', e.getMessage());
      }
      try {
        AXF_CLS_CTRL_Dashboard.getPending(null, null);
        System.assert(false, 'Should have been denied');
      } catch (AuraHandledException e) {
        System.assertNotEquals('Script-thrown exception', e.getMessage());
      }
    }
  }

  @IsTest
  static void emptyMonthReturnsZeroAndNoItems() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      ALT_CLS_DashboardPreview.Pending result = AXF_CLS_CTRL_Dashboard.getPending(
        null,
        null
      );
      System.assertEquals(0, result.total);
      System.assertEquals(0, result.items.size());
      System.assertEquals(
        0,
        AXF_CLS_CTRL_Dashboard.getSources(null).accounts.size()
      );
    }
  }

  @IsTest
  static void excludesCardTransactionsLinkedToAnEntryAndFlagsCardSuggestions() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account holder = holder('Titular', 'AXF_Business');
      AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
        Name = 'Cartão',
        AXF_CC_MD_Holder__c = holder.Id,
        AXF_CC_PKL_Institution__c = '341'
      );
      insert card;
      Date start = Date.today().toStartOfMonth();
      AXF_OBJ_CreditCardTransaction__c linked = new AXF_OBJ_CreditCardTransaction__c(
        AXF_CCT_MD_CreditCard__c = card.Id,
        AXF_CCT_DAT_Date__c = start,
        AXF_CCT_CUR_Amount__c = -15,
        AXF_CCT_TXT_Description__c = 'Já ligada'
      );
      AXF_OBJ_CreditCardTransaction__c matching = new AXF_OBJ_CreditCardTransaction__c(
        AXF_CCT_MD_CreditCard__c = card.Id,
        AXF_CCT_DAT_Date__c = start.addDays(3),
        AXF_CCT_CUR_Amount__c = -80,
        AXF_CCT_CUR_AmountBRL__c = -80,
        AXF_CCT_TXT_Description__c = 'Sugerida'
      );
      insert new List<AXF_OBJ_CreditCardTransaction__c>{ linked, matching };
      insert new List<AXF_OBJ_Entry__c>{
        new AXF_OBJ_Entry__c(
          Name = 'Ligado',
          AXF_ENT_MD_Holder__c = holder.Id,
          AXF_ENT_CUR_Amount__c = 15,
          AXF_ENT_DAT_DueDate__c = start,
          AXF_ENT_PKL_Type__c = 'Expense',
          AXF_ENT_PKL_Status__c = 'Pending',
          AXF_ENT_LKP_CreditCardTransaction__c = linked.Id
        ),
        new AXF_OBJ_Entry__c(
          Name = 'Compra',
          AXF_ENT_MD_Holder__c = holder.Id,
          AXF_ENT_CUR_Amount__c = 80,
          AXF_ENT_DAT_DueDate__c = start.addDays(3),
          AXF_ENT_PKL_Type__c = 'Expense',
          AXF_ENT_PKL_Status__c = 'Pending',
          AXF_ENT_LKP_CreditCard__c = card.Id
        )
      };
      ALT_CLS_DashboardPreview.Pending result = AXF_CLS_CTRL_Dashboard.getPending(
        holder.Id,
        Date.today()
      );
      System.assertEquals(1, result.total);
      System.assertEquals(matching.Id, result.items[0].id);
      System.assert(result.items[0].suggested);
      System.assertEquals(1, result.suggestions);
      System.assert(!result.suggestionsPartial);
    }
  }

  @IsTest
  static void flagsTruncationAndConvertsForeignTransactionsAndCards() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account holder = holder('Titular', 'AXF_Business');
      AXF_OBJ_BankAccount__c account = account(holder.Id, 10);
      Date start = Date.today().toStartOfMonth();
      AXF_OBJ_BankAccountTransaction__c usd = bank(
        account.Id,
        start,
        -100,
        null
      );
      usd.put('CurrencyIsoCode', 'USD');
      insert new List<AXF_OBJ_BankAccountTransaction__c>{
        usd,
        bank(account.Id, start.addDays(1), -1, null)
      };
      AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
        Name = 'Cartão USD',
        AXF_CC_MD_Holder__c = holder.Id,
        AXF_CC_PKL_Institution__c = '341',
        AXF_CC_CUR_Limit__c = 1000,
        AXF_CC_CUR_AvailableLimit__c = 400
      );
      card.put('CurrencyIsoCode', 'USD');
      insert card;
      Decimal rate = [
        SELECT ConversionRate
        FROM CurrencyType
        WHERE IsoCode = 'USD'
      ]
      .ConversionRate;
      ALT_CLS_DashboardPreview.maxRows = 2;
      ALT_CLS_DashboardPreview.Pending result = AXF_CLS_CTRL_Dashboard.getPending(
        holder.Id,
        Date.today()
      );
      System.assert(result.truncated, 'Two rows read, two is the cap');
      ALT_CLS_DashboardPreview.maxRows = 2000;
      result = AXF_CLS_CTRL_Dashboard.getPending(holder.Id, Date.today());
      System.assert(!result.truncated);
      System.assertEquals(
        (-100 / rate).setScale(2),
        result.items[1].amount.setScale(2)
      );
      ALT_CLS_DashboardPreview.Sources sources = AXF_CLS_CTRL_Dashboard.getSources(
        holder.Id
      );
      System.assertEquals(
        (400 / rate).setScale(2),
        sources.cards[0].value.setScale(2)
      );
      System.assertEquals(
        (1000 / rate).setScale(2),
        sources.cards[0].limitTotal.setScale(2)
      );
    }
  }
}
