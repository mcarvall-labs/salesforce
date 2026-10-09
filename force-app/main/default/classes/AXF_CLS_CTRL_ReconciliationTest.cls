@IsTest
private class AXF_CLS_CTRL_ReconciliationTest {
  @TestSetup
  static void setup() {
    ALT_CLS_SyncTestUser.create(
      'axfcr',
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
  }

  private static AXF_OBJ_Entry__c entry(Id cardId, Decimal amount) {
    AXF_OBJ_Entry__c entry = new AXF_OBJ_Entry__c(
      Name = 'Lançamento',
      AXF_ENT_MD_Holder__c = holder.Id,
      AXF_ENT_CUR_Amount__c = amount,
      AXF_ENT_DAT_DueDate__c = DUE,
      AXF_ENT_PKL_Type__c = 'Expense',
      AXF_ENT_PKL_Status__c = 'Pending',
      AXF_ENT_LKP_CreditCard__c = cardId
    );
    insert entry;
    return entry;
  }

  private static AXF_OBJ_BankAccountTransaction__c bank(Decimal amount) {
    AXF_OBJ_BankAccountTransaction__c transactionRecord = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MD_BankAccount__c = account.Id,
      AXF_BAT_DAT_Date__c = DUE,
      AXF_BAT_CUR_Amount__c = amount,
      AXF_BAT_TXT_Description__c = 'Pagamento'
    );
    insert transactionRecord;
    return transactionRecord;
  }

  private static AXF_OBJ_CreditCardTransaction__c purchase(Decimal amount) {
    AXF_OBJ_CreditCardTransaction__c transactionRecord = new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MD_CreditCard__c = card.Id,
      AXF_CCT_DAT_Date__c = DUE,
      AXF_CCT_CUR_Amount__c = amount,
      AXF_CCT_CUR_AmountBRL__c = amount,
      AXF_CCT_TXT_CurrencyCode__c = 'BRL',
      AXF_CCT_TXT_Description__c = 'Compra'
    );
    insert transactionRecord;
    return transactionRecord;
  }

  @IsTest
  static void holdersAreThoseWithAccountsOrCards() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      insert new Account(Name = 'Sem contas');
      List<AXF_CLS_CTRL_Reconciliation.HolderView> holders = AXF_CLS_CTRL_Reconciliation.getHolders();
      System.assertEquals(1, holders.size());
      System.assertEquals(holder.Id, holders[0].id);
      System.assertEquals('Titular', holders[0].name);
    }
  }

  @IsTest
  static void screenDataHasEntriesTransactionsSuggestionsAndSources() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c pending = entry(null, 100);
      AXF_OBJ_Entry__c cardEntry = entry(card.Id, 30);
      AXF_OBJ_BankAccountTransaction__c debit = bank(-100);
      AXF_OBJ_CreditCardTransaction__c purchase = purchase(-30);
      AXF_OBJ_CreditCardTransaction__c linkedPurchase = purchase(-5);
      AXF_OBJ_Entry__c owner = entry(card.Id, 5);
      owner.AXF_ENT_LKP_CreditCardTransaction__c = linkedPurchase.Id;
      update owner;
      AXF_CLS_CTRL_Reconciliation.ScreenData data = AXF_CLS_CTRL_Reconciliation.getData(
        holder.Id,
        '2026-10'
      );
      System.assertEquals(2, data.sources.size());
      System.assertEquals('account', data.sources[0].kind);
      System.assertEquals('card', data.sources[1].kind);
      Set<Id> entryIds = new Set<Id>();
      for (AXF_CLS_CTRL_Reconciliation.EntryView entry : data.entries) {
        entryIds.add(entry.id);
      }
      System.assert(entryIds.contains(pending.Id));
      System.assert(entryIds.contains(cardEntry.Id));
      System.assert(!entryIds.contains(owner.Id));
      System.assertEquals(2, data.transactions.size());
      Map<Id, AXF_CLS_CTRL_Reconciliation.TransactionView> byId = new Map<Id, AXF_CLS_CTRL_Reconciliation.TransactionView>();
      for (
        AXF_CLS_CTRL_Reconciliation.TransactionView view : data.transactions
      ) {
        byId.put(view.id, view);
      }
      System.assertEquals('account', byId.get(debit.Id).source);
      System.assertEquals(-100, byId.get(debit.Id).amount);
      System.assertEquals('card', byId.get(purchase.Id).source);
      System.assertEquals(-30, byId.get(purchase.Id).amountBRL);
      System.assertEquals(2, data.suggestions.size());
      System.assertEquals(null, data.lastReconciledEntryId);
    }
  }

  @IsTest
  static void reconcileThenUnreconcileThroughTheController() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c pending = entry(null, 100);
      AXF_OBJ_BankAccountTransaction__c debit = bank(-100);
      AXF_CLS_CTRL_Reconciliation.PairInput pair = new AXF_CLS_CTRL_Reconciliation.PairInput();
      pair.entryId = pending.Id;
      pair.bankTransactionId = debit.Id;
      List<AXF_CLS_CTRL_Reconciliation.OutcomeView> done = AXF_CLS_CTRL_Reconciliation.reconcile(
        new List<AXF_CLS_CTRL_Reconciliation.PairInput>{ pair, null }
      );
      System.assertEquals(true, done[0].success, '' + done[0].message);
      System.assertEquals(false, done[1].success);
      AXF_CLS_CTRL_Reconciliation.ScreenData data = AXF_CLS_CTRL_Reconciliation.getData(
        holder.Id,
        '2026-10'
      );
      System.assertEquals(pending.Id, data.lastReconciledEntryId);
      System.assertEquals(0, data.entries.size());
      System.assertEquals(0, data.transactions.size());
      List<AXF_CLS_CTRL_Reconciliation.OutcomeView> undone = AXF_CLS_CTRL_Reconciliation.unreconcile(
        new List<Id>{ pending.Id }
      );
      System.assertEquals(true, undone[0].success, '' + undone[0].message);
      System.assertEquals(
        1,
        AXF_CLS_CTRL_Reconciliation.getData(holder.Id, '2026-10').entries.size()
      );
    }
  }

  @IsTest
  static void ignoreAndCreateEntryThroughTheController() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_BankAccountTransaction__c transfer = bank(-500);
      AXF_OBJ_CreditCardTransaction__c fee = purchase(-9);
      List<AXF_CLS_CTRL_Reconciliation.OutcomeView> ignored = AXF_CLS_CTRL_Reconciliation.ignoreTransactions(
        new List<Id>{ transfer.Id },
        null
      );
      System.assertEquals(true, ignored[0].success, '' + ignored[0].message);
      List<AXF_CLS_CTRL_Reconciliation.OutcomeView> created = AXF_CLS_CTRL_Reconciliation.createEntries(
        null,
        new List<Id>{ fee.Id }
      );
      System.assertEquals(true, created[0].success, '' + created[0].message);
      System.assertNotEquals(null, created[0].entryId);
      System.assertEquals(
        0,
        AXF_CLS_CTRL_Reconciliation.getData(holder.Id, '2026-10')
          .transactions.size()
      );
    }
  }

  @IsTest
  static void invalidInputIsRejected() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      for (
        String month : new List<String>{ null, '2026', '2026-13', 'abcd-ef' }
      ) {
        try {
          AXF_CLS_CTRL_Reconciliation.getData(holder.Id, month);
          System.assert(false, 'expected AuraHandledException');
        } catch (AuraHandledException e) {
          System.assertNotEquals(null, e.getMessage());
        }
      }
      try {
        AXF_CLS_CTRL_Reconciliation.getData(null, '2026-10');
        System.assert(false, 'expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assertNotEquals(null, e.getMessage());
      }
      System.assertEquals(
        0,
        AXF_CLS_CTRL_Reconciliation.reconcile(null).size()
      );
    }
  }
}
