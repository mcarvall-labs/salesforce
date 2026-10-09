@IsTest
private class ALT_CLS_ReconciliationSuggestionsTest {
  @TestSetup
  static void setup() {
    ALT_CLS_SyncTestUser.create(
      'axfrs',
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
    insert account;
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
    Id cardId,
    Id invoiceId
  ) {
    AXF_OBJ_Entry__c entry = new AXF_OBJ_Entry__c(
      Name = 'Lançamento',
      AXF_ENT_MD_Holder__c = holder.Id,
      AXF_ENT_CUR_Amount__c = amount,
      CurrencyIsoCode = currencyCode,
      AXF_ENT_DAT_DueDate__c = DUE,
      AXF_ENT_PKL_Type__c = 'Expense',
      AXF_ENT_PKL_Status__c = 'Pending',
      AXF_ENT_LKP_CreditCard__c = cardId,
      AXF_ENT_LKP_Invoice__c = invoiceId
    );
    insert entry;
    return entry;
  }

  private static AXF_OBJ_BankAccountTransaction__c bank(
    Decimal amount,
    Date day
  ) {
    AXF_OBJ_BankAccountTransaction__c transactionRecord = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MD_BankAccount__c = account.Id,
      AXF_BAT_DAT_Date__c = day,
      AXF_BAT_CUR_Amount__c = amount
    );
    insert transactionRecord;
    return transactionRecord;
  }

  private static AXF_OBJ_CreditCardTransaction__c purchase(
    Decimal amount,
    Decimal amountBRL,
    String currencyCode,
    Date day
  ) {
    AXF_OBJ_CreditCardTransaction__c transactionRecord = new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MD_CreditCard__c = card.Id,
      AXF_CCT_DAT_Date__c = day,
      AXF_CCT_CUR_Amount__c = amount,
      AXF_CCT_CUR_AmountBRL__c = amountBRL,
      AXF_CCT_TXT_CurrencyCode__c = currencyCode
    );
    insert transactionRecord;
    return transactionRecord;
  }

  private static List<ALT_CLS_ReconciliationSuggestions.Suggestion> suggest() {
    return new ALT_CLS_ReconciliationSuggestions()
      .suggest(holder.Id, DUE.addDays(-30), DUE.addDays(30));
  }

  @IsTest
  static void suggestsSameValueWithinSevenDays() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c entry = entry(100, 'BRL', null, null);
      AXF_OBJ_BankAccountTransaction__c near = bank(-100, DUE.addDays(7));
      bank(-100, DUE.addDays(8));
      bank(-90, DUE);
      List<ALT_CLS_ReconciliationSuggestions.Suggestion> found = suggest();
      System.assertEquals(1, found.size());
      System.assertEquals(entry.Id, found[0].entryId);
      System.assertEquals(near.Id, found[0].bankTransactionId);
      System.assertEquals(null, found[0].cardTransactionId);
      System.assertEquals(7, found[0].daysApart);
      System.assertEquals(false, found[0].crossCurrency);
    }
  }

  @IsTest
  static void cardEntryOnlyGetsCardTransactionsAndPlainEntryOnlyBank() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c cardEntry = entry(50, 'BRL', card.Id, null);
      AXF_OBJ_Entry__c plainEntry = entry(50, 'BRL', null, null);
      AXF_OBJ_BankAccountTransaction__c bank = bank(-50, DUE);
      AXF_OBJ_CreditCardTransaction__c purchase = purchase(
        -50,
        -50,
        'BRL',
        DUE
      );
      Map<Id, ALT_CLS_ReconciliationSuggestions.Suggestion> byEntry = new Map<Id, ALT_CLS_ReconciliationSuggestions.Suggestion>();
      for (ALT_CLS_ReconciliationSuggestions.Suggestion item : suggest()) {
        byEntry.put(item.entryId, item);
      }
      System.assertEquals(2, byEntry.size());
      System.assertEquals(
        purchase.Id,
        byEntry.get(cardEntry.Id).cardTransactionId
      );
      System.assertEquals(null, byEntry.get(cardEntry.Id).bankTransactionId);
      System.assertEquals(
        bank.Id,
        byEntry.get(plainEntry.Id).bankTransactionId
      );
    }
  }

  @IsTest
  static void invoiceEntryMatchesTheBankPayment() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_CreditCardInvoice__c invoice = new AXF_OBJ_CreditCardInvoice__c(
        AXF_CCI_MD_CreditCard__c = card.Id,
        AXF_CCI_TXT_Period__c = '2026-10',
        AXF_CCI_DAT_DueDate__c = DUE,
        AXF_CCI_CUR_TotalAmount__c = 300,
        AXF_CCI_PKL_Status__c = 'Open'
      );
      insert invoice;
      AXF_OBJ_Entry__c entry = entry(300, 'BRL', card.Id, invoice.Id);
      AXF_OBJ_BankAccountTransaction__c payment = bank(-300, DUE.addDays(-1));
      purchase(-300, -300, 'BRL', DUE);
      List<ALT_CLS_ReconciliationSuggestions.Suggestion> found = suggest();
      System.assertEquals(1, found.size());
      System.assertEquals(payment.Id, found[0].bankTransactionId);
    }
  }

  @IsTest
  static void differentCurrenciesCompareInBrlWithinFivePercent() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      // USD 20 at 0.2 USD per BRL is BRL 100.
      AXF_OBJ_Entry__c within = entry(20, 'USD', null, null);
      AXF_OBJ_BankAccountTransaction__c bank = bank(-104, DUE);
      List<ALT_CLS_ReconciliationSuggestions.Suggestion> found = suggest();
      System.assertEquals(1, found.size());
      System.assertEquals(true, found[0].crossCurrency);
      System.assertEquals(bank.Id, found[0].bankTransactionId);
      delete bank;
      bank(-106, DUE);
      System.assertEquals(0, suggest().size());
      delete within;
    }
  }

  @IsTest
  static void cardPurchaseInDollarsMatchesEntryInDollarsOrBrl() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c usdEntry = entry(20, 'USD', card.Id, null);
      AXF_OBJ_CreditCardTransaction__c dollars = purchase(
        -20,
        -103,
        'USD',
        DUE
      );
      List<ALT_CLS_ReconciliationSuggestions.Suggestion> found = suggest();
      System.assertEquals(1, found.size());
      System.assertEquals(false, found[0].crossCurrency);
      System.assertEquals(dollars.Id, found[0].cardTransactionId);
      delete usdEntry;
      entry(100, 'BRL', card.Id, null);
      found = suggest();
      System.assertEquals(1, found.size());
      System.assertEquals(true, found[0].crossCurrency);
    }
  }

  @IsTest
  static void closestPairWinsAndEachSideIsUsedOnce() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c first = entry(100, 'BRL', null, null);
      AXF_OBJ_Entry__c second = entry(100, 'BRL', null, null);
      AXF_OBJ_BankAccountTransaction__c exact = bank(-100, DUE);
      AXF_OBJ_BankAccountTransaction__c late = bank(-100, DUE.addDays(3));
      List<ALT_CLS_ReconciliationSuggestions.Suggestion> found = suggest();
      System.assertEquals(2, found.size());
      Set<Id> transactions = new Set<Id>{
        found[0].bankTransactionId,
        found[1].bankTransactionId
      };
      System.assertEquals(new Set<Id>{ exact.Id, late.Id }, transactions);
      System.assertNotEquals(found[0].entryId, found[1].entryId);
      System.assertEquals(0, found[0].daysApart);
      System.assert(
        new Set<Id>{ first.Id, second.Id }.contains(found[0].entryId)
      );
    }
  }

  @IsTest
  static void reconciledOrLinkedTransactionsAndEntriesAreNotSuggested() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c entry = entry(100, 'BRL', null, null);
      AXF_OBJ_BankAccountTransaction__c linked = bank(-100, DUE);
      AXF_OBJ_Entry__c owner = entry(100, 'BRL', null, null);
      owner.AXF_ENT_LKP_BankAccountTransaction__c = linked.Id;
      update owner;
      AXF_OBJ_BankAccountTransaction__c done = new AXF_OBJ_BankAccountTransaction__c(
        AXF_BAT_MD_BankAccount__c = account.Id,
        AXF_BAT_DAT_Date__c = DUE,
        AXF_BAT_CUR_Amount__c = -100,
        AXF_BAT_PKL_ReconciliationStatus__c = 'Reconciled'
      );
      insert done;
      System.assertEquals(0, suggest().size());
      System.assertNotEquals(null, entry.Id);
    }
  }

  @IsTest
  static void entryWithAccountOnlyMatchesThatAccount() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_BankAccount__c other = new AXF_OBJ_BankAccount__c(
        Name = 'Outra',
        AXF_BA_MD_Holder__c = holder.Id,
        AXF_BA_PKL_Institution__c = '341',
        AXF_BA_PKL_Type__c = 'Checking'
      );
      insert other;
      AXF_OBJ_Entry__c entry = entry(100, 'BRL', null, null);
      entry.AXF_ENT_LKP_BankAccount__c = other.Id;
      update entry;
      bank(-100, DUE);
      System.assertEquals(0, suggest().size());
    }
  }

  @IsTest
  static void missingFiltersReturnNothing() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      System.assertEquals(
        0,
        new ALT_CLS_ReconciliationSuggestions().suggest(null, DUE, DUE).size()
      );
      System.assertEquals(
        0,
        new ALT_CLS_ReconciliationSuggestions()
          .suggest(holder.Id, null, DUE)
          .size()
      );
    }
  }
}
