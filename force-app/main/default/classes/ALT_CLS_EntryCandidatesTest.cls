@IsTest
private class ALT_CLS_EntryCandidatesTest {
  @TestSetup
  static void setup() {
    ALT_CLS_SyncTestUser.create(
      'axfec',
      new List<String>{
        'AXF_OBJ_Entry__c',
        'AXF_OBJ_BankAccount__c',
        'AXF_OBJ_BankAccountTransaction__c',
        'AXF_OBJ_CreditCard__c',
        'AXF_OBJ_CreditCardInvoice__c',
        'AXF_OBJ_CreditCardTransaction__c'
      }
    );
  }

  private static final Date DUE = Date.newInstance(2026, 10, 10);

  private static Account holder;
  private static AXF_OBJ_BankAccount__c account;
  private static AXF_OBJ_BankAccount__c otherAccount;
  private static AXF_OBJ_CreditCard__c card;

  private static void base() {
    holder = new Account(Name = 'Titular');
    insert holder;
    account = new AXF_OBJ_BankAccount__c(
      Name = 'Conta',
      AXF_BA_MD_Holder__c = holder.Id,
      AXF_BA_PKL_Institution__c = '341',
      AXF_BA_PKL_Type__c = 'Checking'
    );
    otherAccount = new AXF_OBJ_BankAccount__c(
      Name = 'Outra conta',
      AXF_BA_MD_Holder__c = holder.Id,
      AXF_BA_PKL_Institution__c = '341',
      AXF_BA_PKL_Type__c = 'Checking'
    );
    insert new List<AXF_OBJ_BankAccount__c>{ account, otherAccount };
    card = new AXF_OBJ_CreditCard__c(
      Name = 'Cartão',
      AXF_CC_MD_Holder__c = holder.Id,
      AXF_CC_PKL_Institution__c = '341'
    );
    insert card;
    ALT_CLS_ReconciliationSuggestions.rateOverride = new Map<String, Decimal>{
      'USD' => 0.2
    };
  }

  private static AXF_OBJ_Entry__c entry(
    Decimal amount,
    String currencyCode,
    Id accountId,
    Id cardId,
    String status
  ) {
    AXF_OBJ_Entry__c entry = new AXF_OBJ_Entry__c(
      Name = 'Lançamento',
      AXF_ENT_MD_Holder__c = holder.Id,
      AXF_ENT_CUR_Amount__c = amount,
      CurrencyIsoCode = currencyCode,
      AXF_ENT_DAT_DueDate__c = DUE,
      AXF_ENT_PKL_Type__c = 'Expense',
      AXF_ENT_PKL_Status__c = status,
      AXF_ENT_LKP_BankAccount__c = accountId,
      AXF_ENT_LKP_CreditCard__c = cardId
    );
    if (status == 'Realized') {
      entry.AXF_ENT_DAT_PaymentDate__c = DUE;
    }
    insert entry;
    return entry;
  }

  private static AXF_OBJ_BankAccountTransaction__c bank(
    Id accountId,
    Decimal amount,
    Date day
  ) {
    AXF_OBJ_BankAccountTransaction__c transactionRecord = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MD_BankAccount__c = accountId,
      AXF_BAT_DAT_Date__c = day,
      AXF_BAT_CUR_Amount__c = amount,
      AXF_BAT_TXT_Description__c = 'PIX'
    );
    insert transactionRecord;
    return transactionRecord;
  }

  private static AXF_OBJ_CreditCardTransaction__c purchase(
    Decimal amount,
    Date day
  ) {
    AXF_OBJ_CreditCardTransaction__c transactionRecord = new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MD_CreditCard__c = card.Id,
      AXF_CCT_DAT_Date__c = day,
      AXF_CCT_CUR_Amount__c = amount,
      AXF_CCT_CUR_AmountBRL__c = amount,
      AXF_CCT_TXT_CurrencyCode__c = 'BRL'
    );
    insert transactionRecord;
    return transactionRecord;
  }

  @IsTest
  static void listsWindowedCandidatesOrderedAndTagged() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c entry = entry(100, 'BRL', account.Id, null, 'Pending');
      AXF_OBJ_BankAccountTransaction__c sameDay = bank(account.Id, -100, DUE);
      AXF_OBJ_BankAccountTransaction__c nearValue = bank(
        account.Id,
        -103,
        DUE.addDays(2)
      );
      AXF_OBJ_BankAccountTransaction__c nearDate = bank(
        account.Id,
        -100,
        DUE.addDays(-3)
      );
      bank(account.Id, -100, DUE.addDays(8));
      bank(account.Id, -120, DUE);
      bank(account.Id, 100, DUE);
      bank(otherAccount.Id, -100, DUE);
      List<ALT_CLS_EntryCandidates.Candidate> found = new ALT_CLS_EntryCandidates()
        .candidates(entry.Id);
      System.assertEquals(3, found.size());
      System.assertEquals(sameDay.Id, found[0].id);
      System.assertEquals(ALT_CLS_EntryCandidates.TAG_BEST, found[0].tag);
      System.assertEquals('account', found[0].source);
      System.assertEquals('Conta', found[0].accountName);
      System.assertEquals('PIX', found[0].description);
      System.assertEquals(nearValue.Id, found[1].id);
      System.assertEquals(ALT_CLS_EntryCandidates.TAG_VALUE, found[1].tag);
      System.assertEquals(2, found[1].daysApart);
      System.assertEquals(nearDate.Id, found[2].id);
      System.assertEquals(ALT_CLS_EntryCandidates.TAG_DATE, found[2].tag);
      System.assertEquals(3, found[2].daysApart);
    }
  }

  @IsTest
  static void withinToleranceOnlyAcrossCurrencies() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      // 100 BRL entry; 20.00 USD at 0.2 USD per BRL = 100 BRL; 21.5 USD = 107.5 BRL (7.5 %).
      AXF_OBJ_Entry__c entry = entry(100, 'BRL', null, null, 'Pending');
      AXF_OBJ_BankAccountTransaction__c usd = bank(account.Id, -20, DUE);
      usd.put('CurrencyIsoCode', 'USD');
      update usd;
      AXF_OBJ_BankAccountTransaction__c far = bank(account.Id, -21.5, DUE);
      far.put('CurrencyIsoCode', 'USD');
      update far;
      List<ALT_CLS_EntryCandidates.Candidate> found = new ALT_CLS_EntryCandidates()
        .candidates(entry.Id);
      System.assertEquals(1, found.size());
      System.assertEquals(usd.Id, found[0].id);
      System.assertEquals('USD', found[0].currencyCode);
    }
  }

  @IsTest
  static void entryWithoutAccountSeesEveryAccountOfTheHolder() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c entry = entry(100, 'BRL', null, null, 'Pending');
      bank(account.Id, -100, DUE);
      bank(otherAccount.Id, -100, DUE.addDays(1));
      System.assertEquals(
        2,
        new ALT_CLS_EntryCandidates().candidates(entry.Id).size()
      );
    }
  }

  @IsTest
  static void cardEntryOnlyGetsCardTransactions() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c entry = entry(50, 'BRL', null, card.Id, 'Pending');
      bank(account.Id, -50, DUE);
      AXF_OBJ_CreditCardTransaction__c purchase = purchase(-50, DUE);
      List<ALT_CLS_EntryCandidates.Candidate> found = new ALT_CLS_EntryCandidates()
        .candidates(entry.Id);
      System.assertEquals(1, found.size());
      System.assertEquals(purchase.Id, found[0].id);
      System.assertEquals('card', found[0].source);
      System.assertEquals('Cartão', found[0].accountName);
    }
  }

  @IsTest
  static void skipsTransactionsAlreadyLinkedToAnotherEntry() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c entry = entry(100, 'BRL', account.Id, null, 'Pending');
      AXF_OBJ_BankAccountTransaction__c linked = bank(account.Id, -100, DUE);
      AXF_OBJ_BankAccountTransaction__c free = bank(
        account.Id,
        -100,
        DUE.addDays(1)
      );
      AXF_OBJ_Entry__c other = entry(100, 'BRL', account.Id, null, 'Realized');
      other.AXF_ENT_LKP_BankAccountTransaction__c = linked.Id;
      update other;
      List<ALT_CLS_EntryCandidates.Candidate> found = new ALT_CLS_EntryCandidates()
        .candidates(entry.Id);
      System.assertEquals(1, found.size());
      System.assertEquals(free.Id, found[0].id);
    }
  }

  @IsTest
  static void noCandidatesWhenNothingFitsOrEntryIsNotPending() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c pending = entry(100, 'BRL', null, null, 'Pending');
      AXF_OBJ_Entry__c realized = entry(100, 'BRL', null, null, 'Realized');
      bank(account.Id, -300, DUE);
      System.assertEquals(
        0,
        new ALT_CLS_EntryCandidates().candidates(pending.Id).size()
      );
      bank(account.Id, -100, DUE);
      System.assertEquals(
        0,
        new ALT_CLS_EntryCandidates().candidates(realized.Id).size()
      );
      System.assertEquals(
        0,
        new ALT_CLS_EntryCandidates().candidates(null).size()
      );
    }
  }
}
