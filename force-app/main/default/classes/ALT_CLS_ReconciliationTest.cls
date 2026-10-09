@IsTest
private class ALT_CLS_ReconciliationTest {
  @TestSetup
  static void setup() {
    ALT_CLS_SyncTestUser.create(
      'axfrc',
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

  private static AXF_OBJ_Entry__c entry(Id cardId, Id invoiceId) {
    AXF_OBJ_Entry__c entry = new AXF_OBJ_Entry__c(
      Name = 'Lançamento',
      AXF_ENT_MD_Holder__c = holder.Id,
      AXF_ENT_CUR_Amount__c = 100,
      AXF_ENT_DAT_DueDate__c = Date.newInstance(2026, 10, 5),
      AXF_ENT_PKL_Type__c = 'Expense',
      AXF_ENT_PKL_Status__c = 'Pending',
      AXF_ENT_LKP_CreditCard__c = cardId,
      AXF_ENT_LKP_Invoice__c = invoiceId
    );
    insert entry;
    return entry;
  }

  private static AXF_OBJ_BankAccountTransaction__c bankTransaction() {
    return bankTransaction('Pending');
  }

  private static AXF_OBJ_BankAccountTransaction__c bankTransaction(
    String status
  ) {
    AXF_OBJ_BankAccountTransaction__c transactionRecord = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MD_BankAccount__c = account.Id,
      AXF_BAT_DAT_Date__c = Date.newInstance(2026, 10, 7),
      AXF_BAT_CUR_Amount__c = -100,
      AXF_BAT_TXT_Description__c = 'Pagamento',
      AXF_BAT_PKL_ReconciliationStatus__c = status
    );
    insert transactionRecord;
    return transactionRecord;
  }

  private static AXF_OBJ_CreditCardTransaction__c cardTransaction(
    Decimal amount,
    Decimal amountBRL
  ) {
    AXF_OBJ_CreditCardTransaction__c transactionRecord = new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MD_CreditCard__c = card.Id,
      AXF_CCT_DAT_Date__c = Date.newInstance(2026, 10, 6),
      AXF_CCT_CUR_Amount__c = amount,
      AXF_CCT_CUR_AmountBRL__c = amountBRL,
      AXF_CCT_TXT_Description__c = 'Compra'
    );
    insert transactionRecord;
    return transactionRecord;
  }

  private static AXF_OBJ_Entry__c reload(Id id) {
    return [
      SELECT
        AXF_ENT_PKL_Status__c,
        AXF_ENT_DAT_PaymentDate__c,
        AXF_ENT_NUM_RealizedAmountBRL__c,
        AXF_ENT_LKP_BankAccount__c,
        AXF_ENT_LKP_CreditCard__c,
        AXF_ENT_LKP_BankAccountTransaction__c,
        AXF_ENT_LKP_CreditCardTransaction__c
      FROM AXF_OBJ_Entry__c
      WHERE Id = :id
    ];
  }

  @IsTest
  static void reconcilesEntryWithBankTransactionAndFillsTheAccount() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c entry = entry(null, null);
      AXF_OBJ_BankAccountTransaction__c bank = bankTransaction();
      List<ALT_CLS_Reconciliation.Outcome> outcomes = new ALT_CLS_Reconciliation()
        .reconcile(
          new List<ALT_CLS_Reconciliation.Pair>{
            new ALT_CLS_Reconciliation.Pair(entry.Id, bank.Id, null)
          }
        );
      System.assertEquals(true, outcomes[0].success, '' + outcomes[0].message);
      AXF_OBJ_Entry__c saved = reload(entry.Id);
      System.assertEquals('Realized', saved.AXF_ENT_PKL_Status__c);
      System.assertEquals(
        Date.newInstance(2026, 10, 7),
        saved.AXF_ENT_DAT_PaymentDate__c
      );
      System.assertEquals(100, saved.AXF_ENT_NUM_RealizedAmountBRL__c);
      System.assertEquals(account.Id, saved.AXF_ENT_LKP_BankAccount__c);
      System.assertEquals(bank.Id, saved.AXF_ENT_LKP_BankAccountTransaction__c);
      System.assertEquals(
        'Reconciled',
        [
          SELECT AXF_BAT_PKL_ReconciliationStatus__c
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE Id = :bank.Id
        ]
        .AXF_BAT_PKL_ReconciliationStatus__c
      );
    }
  }

  @IsTest
  static void cardEntryReconcilesOnlyWithCardTransactionUsingTheBrlAmount() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c entry = entry(card.Id, null);
      AXF_OBJ_BankAccountTransaction__c bank = bankTransaction();
      AXF_OBJ_CreditCardTransaction__c purchase = cardTransaction(-20, -105.5);
      ALT_CLS_Reconciliation service = new ALT_CLS_Reconciliation();
      ALT_CLS_Reconciliation.Outcome crossed = service.reconcile(
        new List<ALT_CLS_Reconciliation.Pair>{
          new ALT_CLS_Reconciliation.Pair(entry.Id, bank.Id, null)
        }
      )[0];
      System.assertEquals(false, crossed.success);
      System.assert(crossed.message.contains('cartão'));
      ALT_CLS_Reconciliation.Outcome ok = service.reconcile(
        new List<ALT_CLS_Reconciliation.Pair>{
          new ALT_CLS_Reconciliation.Pair(entry.Id, null, purchase.Id)
        }
      )[0];
      System.assertEquals(true, ok.success, '' + ok.message);
      AXF_OBJ_Entry__c saved = reload(entry.Id);
      System.assertEquals(105.5, saved.AXF_ENT_NUM_RealizedAmountBRL__c);
      System.assertEquals(
        purchase.Id,
        saved.AXF_ENT_LKP_CreditCardTransaction__c
      );
      System.assertEquals(
        'Reconciled',
        [
          SELECT AXF_CCT_PKL_ReconciliationStatus__c
          FROM AXF_OBJ_CreditCardTransaction__c
          WHERE Id = :purchase.Id
        ]
        .AXF_CCT_PKL_ReconciliationStatus__c
      );
    }
  }

  @IsTest
  static void entryWithoutCardRejectsCardTransaction() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c entry = entry(null, null);
      AXF_OBJ_CreditCardTransaction__c purchase = cardTransaction(-20, -20);
      ALT_CLS_Reconciliation.Outcome outcome = new ALT_CLS_Reconciliation()
        .reconcile(
          new List<ALT_CLS_Reconciliation.Pair>{
            new ALT_CLS_Reconciliation.Pair(entry.Id, null, purchase.Id)
          }
        )[0];
      System.assertEquals(false, outcome.success);
      System.assertEquals('Pending', reload(entry.Id).AXF_ENT_PKL_Status__c);
    }
  }

  @IsTest
  static void invoiceEntryReconcilesWithBankPaymentAndKeepsTheCard() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_CreditCardInvoice__c invoice = new AXF_OBJ_CreditCardInvoice__c(
        AXF_CCI_MD_CreditCard__c = card.Id,
        AXF_CCI_TXT_Period__c = '2026-10',
        AXF_CCI_DAT_DueDate__c = Date.newInstance(2026, 10, 5),
        AXF_CCI_CUR_TotalAmount__c = 100,
        AXF_CCI_PKL_Status__c = 'Open'
      );
      insert invoice;
      AXF_OBJ_Entry__c entry = entry(card.Id, invoice.Id);
      AXF_OBJ_BankAccountTransaction__c payment = bankTransaction();
      ALT_CLS_Reconciliation service = new ALT_CLS_Reconciliation();
      ALT_CLS_Reconciliation.Outcome ok = service.reconcile(
        new List<ALT_CLS_Reconciliation.Pair>{
          new ALT_CLS_Reconciliation.Pair(entry.Id, payment.Id, null)
        }
      )[0];
      System.assertEquals(true, ok.success, '' + ok.message);
      AXF_OBJ_Entry__c saved = reload(entry.Id);
      System.assertEquals(card.Id, saved.AXF_ENT_LKP_CreditCard__c);
      System.assertEquals(null, saved.AXF_ENT_LKP_BankAccount__c);
      AXF_OBJ_CreditCardTransaction__c purchase = cardTransaction(-20, -20);
      AXF_OBJ_Entry__c other = entry(card.Id, invoice.Id);
      System.assertEquals(
        false,
        service.reconcile(
            new List<ALT_CLS_Reconciliation.Pair>{
              new ALT_CLS_Reconciliation.Pair(other.Id, null, purchase.Id)
            }
          )[0]
          .success
      );
    }
  }

  @IsTest
  static void aTransactionLinksToOneEntryOnly() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c first = entry(null, null);
      AXF_OBJ_Entry__c second = entry(null, null);
      AXF_OBJ_BankAccountTransaction__c bank = bankTransaction();
      ALT_CLS_Reconciliation service = new ALT_CLS_Reconciliation();
      System.assertEquals(
        true,
        service.reconcile(
            new List<ALT_CLS_Reconciliation.Pair>{
              new ALT_CLS_Reconciliation.Pair(first.Id, bank.Id, null)
            }
          )[0]
          .success
      );
      ALT_CLS_Reconciliation.Outcome again = service.reconcile(
        new List<ALT_CLS_Reconciliation.Pair>{
          new ALT_CLS_Reconciliation.Pair(second.Id, bank.Id, null)
        }
      )[0];
      System.assertEquals(false, again.success);
      System.assertEquals('Pending', reload(second.Id).AXF_ENT_PKL_Status__c);
    }
  }

  @IsTest
  static void batchSucceedsAndFailsPerPair() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c good = entry(null, null);
      AXF_OBJ_Entry__c cardEntry = entry(card.Id, null);
      AXF_OBJ_BankAccountTransaction__c bank = bankTransaction();
      AXF_OBJ_BankAccountTransaction__c otherBank = bankTransaction();
      List<ALT_CLS_Reconciliation.Outcome> outcomes = new ALT_CLS_Reconciliation()
        .reconcile(
          new List<ALT_CLS_Reconciliation.Pair>{
            new ALT_CLS_Reconciliation.Pair(good.Id, bank.Id, null),
            new ALT_CLS_Reconciliation.Pair(cardEntry.Id, otherBank.Id, null),
            new ALT_CLS_Reconciliation.Pair(null, otherBank.Id, null),
            new ALT_CLS_Reconciliation.Pair(good.Id, bank.Id, bank.Id)
          }
        );
      System.assertEquals(4, outcomes.size());
      System.assertEquals(true, outcomes[0].success, '' + outcomes[0].message);
      System.assertEquals(false, outcomes[1].success);
      System.assertEquals(false, outcomes[2].success);
      System.assertEquals(false, outcomes[3].success);
      System.assertEquals(
        'Pending',
        [
          SELECT AXF_BAT_PKL_ReconciliationStatus__c
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE Id = :otherBank.Id
        ]
        .AXF_BAT_PKL_ReconciliationStatus__c
      );
    }
  }

  @IsTest
  static void duplicatedEntryInTheSameBatchIsRejected() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c entry = entry(null, null);
      AXF_OBJ_BankAccountTransaction__c first = bankTransaction();
      AXF_OBJ_BankAccountTransaction__c second = bankTransaction();
      List<ALT_CLS_Reconciliation.Outcome> outcomes = new ALT_CLS_Reconciliation()
        .reconcile(
          new List<ALT_CLS_Reconciliation.Pair>{
            new ALT_CLS_Reconciliation.Pair(entry.Id, first.Id, null),
            new ALT_CLS_Reconciliation.Pair(entry.Id, second.Id, null)
          }
        );
      System.assertEquals(true, outcomes[0].success, '' + outcomes[0].message);
      System.assertEquals(false, outcomes[1].success);
    }
  }

  @IsTest
  static void transactionOfAnotherAccountOrHolderIsRejected() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_BankAccount__c second = new AXF_OBJ_BankAccount__c(
        Name = 'Outra',
        AXF_BA_MD_Holder__c = holder.Id,
        AXF_BA_PKL_Institution__c = '341',
        AXF_BA_PKL_Type__c = 'Checking'
      );
      insert second;
      AXF_OBJ_Entry__c entry = new AXF_OBJ_Entry__c(
        Name = 'Lançamento',
        AXF_ENT_MD_Holder__c = holder.Id,
        AXF_ENT_CUR_Amount__c = 100,
        AXF_ENT_DAT_DueDate__c = Date.today(),
        AXF_ENT_PKL_Type__c = 'Expense',
        AXF_ENT_PKL_Status__c = 'Pending',
        AXF_ENT_LKP_BankAccount__c = second.Id
      );
      insert entry;
      AXF_OBJ_BankAccountTransaction__c bank = bankTransaction();
      ALT_CLS_Reconciliation.Outcome outcome = new ALT_CLS_Reconciliation()
        .reconcile(
          new List<ALT_CLS_Reconciliation.Pair>{
            new ALT_CLS_Reconciliation.Pair(entry.Id, bank.Id, null)
          }
        )[0];
      System.assertEquals(false, outcome.success);
      System.assert(outcome.message.contains('outra conta'));
    }
  }

  @IsTest
  static void ignoredTransactionCannotBeReconciled() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c entry = entry(null, null);
      AXF_OBJ_BankAccountTransaction__c bank = bankTransaction('Ignored');
      System.assertEquals(
        false,
        new ALT_CLS_Reconciliation()
            .reconcile(
              new List<ALT_CLS_Reconciliation.Pair>{
                new ALT_CLS_Reconciliation.Pair(entry.Id, bank.Id, null)
              }
            )[0]
          .success
      );
    }
  }

  @IsTest
  static void unreconcileRevertsEntryAndTransaction() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c bankEntry = entry(null, null);
      AXF_OBJ_Entry__c cardEntry = entry(card.Id, null);
      AXF_OBJ_BankAccountTransaction__c bank = bankTransaction();
      AXF_OBJ_CreditCardTransaction__c purchase = cardTransaction(-20, -20);
      ALT_CLS_Reconciliation service = new ALT_CLS_Reconciliation();
      service.reconcile(
        new List<ALT_CLS_Reconciliation.Pair>{
          new ALT_CLS_Reconciliation.Pair(bankEntry.Id, bank.Id, null),
          new ALT_CLS_Reconciliation.Pair(cardEntry.Id, null, purchase.Id)
        }
      );
      List<ALT_CLS_Reconciliation.Outcome> outcomes = service.unreconcile(
        new List<Id>{ bankEntry.Id, cardEntry.Id }
      );
      System.assertEquals(true, outcomes[0].success, '' + outcomes[0].message);
      System.assertEquals(true, outcomes[1].success, '' + outcomes[1].message);
      AXF_OBJ_Entry__c saved = reload(bankEntry.Id);
      System.assertEquals('Pending', saved.AXF_ENT_PKL_Status__c);
      System.assertEquals(null, saved.AXF_ENT_DAT_PaymentDate__c);
      System.assertEquals(null, saved.AXF_ENT_NUM_RealizedAmountBRL__c);
      System.assertEquals(null, saved.AXF_ENT_LKP_BankAccountTransaction__c);
      System.assertEquals(
        'Pending',
        [
          SELECT AXF_BAT_PKL_ReconciliationStatus__c
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE Id = :bank.Id
        ]
        .AXF_BAT_PKL_ReconciliationStatus__c
      );
      System.assertEquals(
        'Pending',
        [
          SELECT AXF_CCT_PKL_ReconciliationStatus__c
          FROM AXF_OBJ_CreditCardTransaction__c
          WHERE Id = :purchase.Id
        ]
        .AXF_CCT_PKL_ReconciliationStatus__c
      );
      System.assertEquals(
        true,
        service.reconcile(
            new List<ALT_CLS_Reconciliation.Pair>{
              new ALT_CLS_Reconciliation.Pair(bankEntry.Id, bank.Id, null)
            }
          )[0]
          .success
      );
    }
  }

  @IsTest
  static void unreconcileRejectsEntryNotReconciledAndInvalidInput() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_Entry__c entry = entry(null, null);
      List<ALT_CLS_Reconciliation.Outcome> outcomes = new ALT_CLS_Reconciliation()
        .unreconcile(new List<Id>{ entry.Id, null, entry.Id });
      System.assertEquals(false, outcomes[0].success);
      System.assertEquals(false, outcomes[1].success);
      System.assertEquals(false, outcomes[2].success);
      System.assertEquals(
        0,
        new ALT_CLS_Reconciliation().reconcile(null).size()
      );
      System.assertEquals(
        0,
        new ALT_CLS_Reconciliation().unreconcile(null).size()
      );
    }
  }
}
