@IsTest
private class ALT_CLS_ReconciliationActionsTest {
  @TestSetup
  static void setup() {
    ALT_CLS_SyncTestUser.create(
      'axfra',
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

  private static AXF_OBJ_BankAccountTransaction__c bank(
    Decimal amount,
    String status
  ) {
    AXF_OBJ_BankAccountTransaction__c transactionRecord = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MD_BankAccount__c = account.Id,
      AXF_BAT_DAT_Date__c = Date.newInstance(2026, 10, 7),
      AXF_BAT_CUR_Amount__c = amount,
      AXF_BAT_TXT_Description__c = 'PIX Mercado',
      AXF_BAT_PKL_ReconciliationStatus__c = status
    );
    insert transactionRecord;
    return transactionRecord;
  }

  private static AXF_OBJ_CreditCardTransaction__c purchase(
    Decimal amount,
    Decimal amountBRL,
    String currencyCode,
    String status
  ) {
    AXF_OBJ_CreditCardTransaction__c transactionRecord = new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MD_CreditCard__c = card.Id,
      AXF_CCT_DAT_Date__c = Date.newInstance(2026, 10, 6),
      AXF_CCT_CUR_Amount__c = amount,
      AXF_CCT_CUR_AmountBRL__c = amountBRL,
      AXF_CCT_TXT_CurrencyCode__c = currencyCode,
      AXF_CCT_TXT_Description__c = 'Loja',
      AXF_CCT_PKL_ReconciliationStatus__c = status
    );
    insert transactionRecord;
    return transactionRecord;
  }

  private static String bankStatus(Id id) {
    return [
      SELECT AXF_BAT_PKL_ReconciliationStatus__c
      FROM AXF_OBJ_BankAccountTransaction__c
      WHERE Id = :id
    ]
    .AXF_BAT_PKL_ReconciliationStatus__c;
  }

  private static String cardStatus(Id id) {
    return [
      SELECT AXF_CCT_PKL_ReconciliationStatus__c
      FROM AXF_OBJ_CreditCardTransaction__c
      WHERE Id = :id
    ]
    .AXF_CCT_PKL_ReconciliationStatus__c;
  }

  @IsTest
  static void ignoreMarksBankAndCardTransactionsIgnored() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_BankAccountTransaction__c transfer = bank(-100, 'Pending');
      AXF_OBJ_CreditCardTransaction__c fee = purchase(-9, -9, 'BRL', null);
      List<ALT_CLS_ReconciliationActions.Outcome> outcomes = new ALT_CLS_ReconciliationActions()
        .ignore(new List<Id>{ transfer.Id }, new List<Id>{ fee.Id });
      System.assertEquals(2, outcomes.size());
      System.assertEquals(true, outcomes[0].success, '' + outcomes[0].message);
      System.assertEquals(true, outcomes[1].success, '' + outcomes[1].message);
      System.assertEquals('Ignored', bankStatus(transfer.Id));
      System.assertEquals('Ignored', cardStatus(fee.Id));
    }
  }

  @IsTest
  static void ignoreRejectsDoneLinkedMissingAndRepeatedTransactions() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_BankAccountTransaction__c done = bank(-1, 'Reconciled');
      AXF_OBJ_BankAccountTransaction__c linked = bank(-2, 'Pending');
      insert new AXF_OBJ_Entry__c(
        Name = 'Dono',
        AXF_ENT_MD_Holder__c = holder.Id,
        AXF_ENT_CUR_Amount__c = 2,
        AXF_ENT_DAT_DueDate__c = Date.today(),
        AXF_ENT_PKL_Type__c = 'Expense',
        AXF_ENT_PKL_Status__c = 'Pending',
        AXF_ENT_LKP_BankAccountTransaction__c = linked.Id
      );
      AXF_OBJ_BankAccountTransaction__c fine = bank(-3, 'Pending');
      List<ALT_CLS_ReconciliationActions.Outcome> outcomes = new ALT_CLS_ReconciliationActions()
        .ignore(
          new List<Id>{ done.Id, linked.Id, holder.Id, fine.Id, fine.Id, null },
          null
        );
      System.assert(outcomes[0].message.contains('conciliada ou ignorada'));
      System.assert(outcomes[1].message.contains('ligada'));
      System.assert(outcomes[2].message.contains('não encontrada'));
      System.assertEquals(true, outcomes[3].success, '' + outcomes[3].message);
      System.assertEquals(false, outcomes[4].success);
      System.assertEquals(false, outcomes[5].success);
      System.assertEquals('Pending', bankStatus(linked.Id));
    }
  }

  @IsTest
  static void createEntryFromBankDebitAndCredit() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_BankAccountTransaction__c debit = bank(-35.5, null);
      AXF_OBJ_BankAccountTransaction__c credit = bank(120, 'Pending');
      List<ALT_CLS_ReconciliationActions.Outcome> outcomes = new ALT_CLS_ReconciliationActions()
        .createEntries(new List<Id>{ debit.Id, credit.Id }, null);
      System.assertEquals(true, outcomes[0].success, '' + outcomes[0].message);
      System.assertEquals(true, outcomes[1].success, '' + outcomes[1].message);
      AXF_OBJ_Entry__c expense = [
        SELECT
          Name,
          AXF_ENT_PKL_Type__c,
          AXF_ENT_PKL_Status__c,
          AXF_ENT_CUR_Amount__c,
          AXF_ENT_DAT_DueDate__c,
          AXF_ENT_DAT_PaymentDate__c,
          AXF_ENT_NUM_RealizedAmountBRL__c,
          AXF_ENT_LKP_BankAccount__c,
          AXF_ENT_LKP_BankAccountTransaction__c,
          AXF_ENT_LKP_Category__c,
          AXF_ENT_MD_Holder__c
        FROM AXF_OBJ_Entry__c
        WHERE Id = :outcomes[0].entryId
      ];
      System.assertEquals('Expense', expense.AXF_ENT_PKL_Type__c);
      System.assertEquals('Realized', expense.AXF_ENT_PKL_Status__c);
      System.assertEquals(35.5, expense.AXF_ENT_CUR_Amount__c);
      System.assertEquals(35.5, expense.AXF_ENT_NUM_RealizedAmountBRL__c);
      System.assertEquals(
        Date.newInstance(2026, 10, 7),
        expense.AXF_ENT_DAT_PaymentDate__c
      );
      System.assertEquals(
        Date.newInstance(2026, 10, 7),
        expense.AXF_ENT_DAT_DueDate__c
      );
      System.assertEquals(account.Id, expense.AXF_ENT_LKP_BankAccount__c);
      System.assertEquals(
        debit.Id,
        expense.AXF_ENT_LKP_BankAccountTransaction__c
      );
      System.assertEquals(null, expense.AXF_ENT_LKP_Category__c);
      System.assertEquals(holder.Id, expense.AXF_ENT_MD_Holder__c);
      System.assertEquals('PIX Mercado', expense.Name);
      System.assertEquals(
        'Income',
        [
          SELECT AXF_ENT_PKL_Type__c
          FROM AXF_OBJ_Entry__c
          WHERE Id = :outcomes[1].entryId
        ]
        .AXF_ENT_PKL_Type__c
      );
      System.assertEquals('Reconciled', bankStatus(debit.Id));
      System.assertEquals('Reconciled', bankStatus(credit.Id));
    }
  }

  @IsTest
  static void createEntryFromCardPurchaseKeepsTheCardAndNoInvoice() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_CreditCardTransaction__c usd = purchase(-20, -105.5, 'USD', null);
      ALT_CLS_ReconciliationActions.Outcome outcome = new ALT_CLS_ReconciliationActions()
        .createEntries(null, new List<Id>{ usd.Id })[0];
      System.assertEquals(true, outcome.success, '' + outcome.message);
      AXF_OBJ_Entry__c entry = [
        SELECT
          CurrencyIsoCode,
          AXF_ENT_CUR_Amount__c,
          AXF_ENT_NUM_RealizedAmountBRL__c,
          AXF_ENT_LKP_CreditCard__c,
          AXF_ENT_LKP_CreditCardTransaction__c,
          AXF_ENT_LKP_Invoice__c,
          AXF_ENT_FOR_AffectsCash__c
        FROM AXF_OBJ_Entry__c
        WHERE Id = :outcome.entryId
      ];
      System.assertEquals('USD', entry.CurrencyIsoCode);
      System.assertEquals(20, entry.AXF_ENT_CUR_Amount__c);
      System.assertEquals(105.5, entry.AXF_ENT_NUM_RealizedAmountBRL__c);
      System.assertEquals(card.Id, entry.AXF_ENT_LKP_CreditCard__c);
      System.assertEquals(usd.Id, entry.AXF_ENT_LKP_CreditCardTransaction__c);
      System.assertEquals(null, entry.AXF_ENT_LKP_Invoice__c);
      System.assertEquals(false, entry.AXF_ENT_FOR_AffectsCash__c);
      System.assertEquals('Reconciled', cardStatus(usd.Id));
    }
  }

  @IsTest
  static void createEntryRejectsWhatCannotBecomeAnEntry() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_BankAccountTransaction__c ignored = bank(-5, 'Ignored');
      AXF_OBJ_CreditCardTransaction__c foreign = purchase(
        -20,
        null,
        'USD',
        null
      );
      AXF_OBJ_BankAccountTransaction__c fine = bank(-7, null);
      List<ALT_CLS_ReconciliationActions.Outcome> outcomes = new ALT_CLS_ReconciliationActions()
        .createEntries(
          new List<Id>{ ignored.Id, fine.Id },
          new List<Id>{ foreign.Id }
        );
      System.assert(outcomes[0].message.contains('conciliada ou ignorada'));
      System.assertEquals(true, outcomes[1].success, '' + outcomes[1].message);
      System.assert(outcomes[2].message.contains('moeda estrangeira'));
      System.assertEquals(1, [SELECT COUNT() FROM AXF_OBJ_Entry__c]);
      System.assertEquals('Ignored', bankStatus(ignored.Id));
    }
  }

  @IsTest
  static void createEntryTwiceForTheSameTransactionIsRejected() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_BankAccountTransaction__c bank = bank(-10, null);
      ALT_CLS_ReconciliationActions service = new ALT_CLS_ReconciliationActions();
      System.assertEquals(
        true,
        service.createEntries(new List<Id>{ bank.Id }, null)[0].success
      );
      ALT_CLS_ReconciliationActions.Outcome again = service.createEntries(
        new List<Id>{ bank.Id },
        null
      )[0];
      System.assertEquals(false, again.success);
      System.assertEquals(1, [SELECT COUNT() FROM AXF_OBJ_Entry__c]);
    }
  }

  @IsTest
  static void mixedBatchCreatesEveryEntryAndEmptyInputIsHarmless() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      List<Id> banks = new List<Id>();
      List<Id> cards = new List<Id>();
      for (Integer i = 0; i < 6; i++) {
        banks.add(bank(-1 - i, null).Id);
        cards.add(purchase(-1 - i, -1 - i, 'BRL', null).Id);
      }
      for (
        ALT_CLS_ReconciliationActions.Outcome outcome : new ALT_CLS_ReconciliationActions()
          .createEntries(banks, cards)
      ) {
        System.assertEquals(true, outcome.success, '' + outcome.message);
      }
      System.assertEquals(12, [SELECT COUNT() FROM AXF_OBJ_Entry__c]);
      System.assertEquals(
        0,
        new ALT_CLS_ReconciliationActions().createEntries(null, null).size()
      );
      System.assertEquals(
        0,
        new ALT_CLS_ReconciliationActions().ignore(null, null).size()
      );
    }
  }

  @IsTest
  static void aFailingEntryRollsBackAndTheRestStillGetTheirEntries() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_BankAccountTransaction__c good = bank(-10, null);
      AXF_OBJ_CreditCardTransaction__c goodCard = purchase(-5, -5, 'BRL', null);
      // JPY is not an active currency in the org, so the Entry insert fails for this one.
      AXF_OBJ_CreditCardTransaction__c bad = purchase(-1000, -35, 'JPY', null);
      List<ALT_CLS_ReconciliationActions.Outcome> outcomes = new ALT_CLS_ReconciliationActions()
        .createEntries(
          new List<Id>{ good.Id },
          new List<Id>{ bad.Id, goodCard.Id }
        );
      System.assertEquals(true, outcomes[0].success, '' + outcomes[0].message);
      System.assertEquals(false, outcomes[1].success);
      System.assertNotEquals(null, outcomes[1].message);
      System.assertEquals(null, outcomes[1].entryId);
      System.assertEquals(true, outcomes[2].success, '' + outcomes[2].message);
      System.assertEquals(2, [SELECT COUNT() FROM AXF_OBJ_Entry__c]);
      System.assertEquals('Reconciled', bankStatus(good.Id));
      System.assertEquals('Reconciled', cardStatus(goodCard.Id));
      System.assertNotEquals('Reconciled', cardStatus(bad.Id));
    }
  }

  @IsTest
  static void zeroAmountAndForeignBankTransactionsDoNotBecomeEntries() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_BankAccountTransaction__c zero = bank(0, null);
      AXF_OBJ_BankAccountTransaction__c usd = new AXF_OBJ_BankAccountTransaction__c(
        AXF_BAT_MD_BankAccount__c = account.Id,
        AXF_BAT_DAT_Date__c = Date.newInstance(2026, 10, 7),
        AXF_BAT_CUR_Amount__c = -20,
        CurrencyIsoCode = 'USD'
      );
      insert usd;
      List<ALT_CLS_ReconciliationActions.Outcome> outcomes = new ALT_CLS_ReconciliationActions()
        .createEntries(new List<Id>{ zero.Id, usd.Id }, null);
      System.assertEquals(false, outcomes[0].success);
      System.assertEquals(false, outcomes[1].success);
      System.assert(outcomes[1].message.contains('moeda estrangeira'));
      System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_Entry__c]);
      ALT_CLS_ReconciliationActions.Outcome ignored = new ALT_CLS_ReconciliationActions()
        .ignore(new List<Id>{ usd.Id }, null)[0];
      System.assertEquals(true, ignored.success, '' + ignored.message);
    }
  }
}
