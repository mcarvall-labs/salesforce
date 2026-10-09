/**
 * Acceptance of the card purchases in USD (E6-11): the transaction keeps the original amount and the
 * BRL amount on the invoice, the invoice lines show both, and a purchase is suggested and reconciled
 * with an Entry in USD (same currency, equal amount) or in BRL (compared in BRL, 5 % tolerance),
 * always realizing the BRL value of the invoice.
 */
@IsTest
private class ALT_CLS_ForeignCurrencyCardTest {
  @TestSetup
  static void setup() {
    ALT_CLS_SyncTestUser.create(
      'axffc',
      new List<String>{
        'AXF_OBJ_Entry__c',
        'AXF_OBJ_CreditCard__c',
        'AXF_OBJ_CreditCardInvoice__c',
        'AXF_OBJ_CreditCardTransaction__c'
      }
    );
  }

  private static final Date DAY = Date.newInstance(2026, 10, 15);

  private static Account holder;
  private static AXF_OBJ_CreditCard__c card;
  private static AXF_OBJ_CreditCardInvoice__c invoice;

  private static void base() {
    holder = new Account(Name = 'Titular');
    insert holder;
    card = new AXF_OBJ_CreditCard__c(
      Name = 'Cartão',
      AXF_CC_MD_Holder__c = holder.Id,
      AXF_CC_PKL_Institution__c = '341'
    );
    insert card;
    invoice = new AXF_OBJ_CreditCardInvoice__c(
      AXF_CCI_MD_CreditCard__c = card.Id,
      AXF_CCI_TXT_Period__c = '2026-10',
      AXF_CCI_DAT_DueDate__c = Date.newInstance(2026, 10, 20),
      AXF_CCI_CUR_TotalAmount__c = 105.5,
      AXF_CCI_PKL_Status__c = 'Open'
    );
    insert invoice;
    ALT_CLS_ReconciliationSuggestions.rateOverride = new Map<String, Decimal>{
      'USD' => 0.2
    };
  }

  // USD 20 charged as BRL 105.50 on the invoice.
  private static AXF_OBJ_CreditCardTransaction__c dollarPurchase(
    Decimal amountBRL
  ) {
    AXF_OBJ_CreditCardTransaction__c purchase = new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MD_CreditCard__c = card.Id,
      AXF_CCT_LKP_Invoice__c = invoice.Id,
      AXF_CCT_DAT_Date__c = DAY,
      AXF_CCT_TXT_Description__c = 'STREAMING SERVICE (EUA) US$ 20,00',
      AXF_CCT_CUR_Amount__c = -20,
      AXF_CCT_CUR_AmountBRL__c = amountBRL,
      AXF_CCT_TXT_CurrencyCode__c = 'USD'
    );
    insert purchase;
    return purchase;
  }

  private static AXF_OBJ_Entry__c entry(Decimal amount, String currencyCode) {
    AXF_OBJ_Entry__c entry = new AXF_OBJ_Entry__c(
      Name = 'Streaming',
      AXF_ENT_MD_Holder__c = holder.Id,
      AXF_ENT_CUR_Amount__c = amount,
      CurrencyIsoCode = currencyCode,
      AXF_ENT_DAT_DueDate__c = DAY,
      AXF_ENT_PKL_Type__c = 'Expense',
      AXF_ENT_PKL_Status__c = 'Pending',
      AXF_ENT_LKP_CreditCard__c = card.Id
    );
    insert entry;
    return entry;
  }

  private static List<ALT_CLS_ReconciliationSuggestions.Suggestion> suggest() {
    return new ALT_CLS_ReconciliationSuggestions()
      .suggest(holder.Id, DAY.addDays(-30), DAY.addDays(30));
  }

  private static ALT_CLS_Reconciliation.Outcome reconcile(
    AXF_OBJ_Entry__c entry,
    AXF_OBJ_CreditCardTransaction__c purchase
  ) {
    return new ALT_CLS_Reconciliation()
      .reconcile(
        new List<ALT_CLS_Reconciliation.Pair>{
          new ALT_CLS_Reconciliation.Pair(entry.Id, null, purchase.Id)
        }
      )[0];
  }

  private static AXF_OBJ_Entry__c reload(Id id) {
    return [
      SELECT
        AXF_ENT_PKL_Status__c,
        CurrencyIsoCode,
        AXF_ENT_CUR_Amount__c,
        AXF_ENT_NUM_RealizedAmountBRL__c
      FROM AXF_OBJ_Entry__c
      WHERE Id = :id
    ];
  }

  @IsTest
  static void invoiceLinesShowTheOriginalAndTheBrlAmount() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      dollarPurchase(-105.5);
      List<ALT_CLS_CardInvoices.Line> lines = new ALT_CLS_CardInvoices()
        .lines(invoice.Id);
      System.assertEquals(1, lines.size());
      System.assertEquals(-20, lines[0].amount);
      System.assertEquals('USD', lines[0].originalCurrency);
      System.assertEquals(-105.5, lines[0].amountBRL);
      System.assertEquals(
        105.5,
        new ALT_CLS_CardInvoices().invoices(card.Id)[0].totalAmount
      );
      System.assertEquals(
        'BRL',
        new ALT_CLS_CardInvoices().invoices(card.Id)[0].currencyCode
      );
    }
  }

  @IsTest
  static void entryInDollarsMatchesTheDollarAmountAndRealizesTheInvoiceBrl() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_CreditCardTransaction__c purchase = dollarPurchase(-105.5);
      AXF_OBJ_Entry__c dollars = entry(20, 'USD');
      List<ALT_CLS_ReconciliationSuggestions.Suggestion> found = suggest();
      System.assertEquals(1, found.size());
      System.assertEquals(false, found[0].crossCurrency);
      System.assertEquals(purchase.Id, found[0].cardTransactionId);
      ALT_CLS_Reconciliation.Outcome outcome = reconcile(dollars, purchase);
      System.assertEquals(true, outcome.success, '' + outcome.message);
      AXF_OBJ_Entry__c saved = reload(dollars.Id);
      System.assertEquals('Realized', saved.AXF_ENT_PKL_Status__c);
      System.assertEquals('USD', saved.CurrencyIsoCode);
      System.assertEquals(20, saved.AXF_ENT_CUR_Amount__c);
      System.assertEquals(105.5, saved.AXF_ENT_NUM_RealizedAmountBRL__c);
    }
  }

  @IsTest
  static void entryInReaisMatchesTheInvoiceBrlWithinFivePercent() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_CreditCardTransaction__c purchase = dollarPurchase(-105.5);
      AXF_OBJ_Entry__c reais = entry(108, 'BRL');
      List<ALT_CLS_ReconciliationSuggestions.Suggestion> found = suggest();
      System.assertEquals(1, found.size());
      System.assertEquals(true, found[0].crossCurrency);
      ALT_CLS_Reconciliation.Outcome outcome = reconcile(reais, purchase);
      System.assertEquals(true, outcome.success, '' + outcome.message);
      System.assertEquals(
        105.5,
        reload(reais.Id).AXF_ENT_NUM_RealizedAmountBRL__c
      );
    }
  }

  @IsTest
  static void entryInReaisOutsideTheToleranceIsNotSuggested() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      dollarPurchase(-105.5);
      entry(120, 'BRL');
      System.assertEquals(0, suggest().size());
    }
  }

  @IsTest
  static void purchaseWithoutTheInvoiceBrlAmountIsNotSuggestedAndNotReconciled() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_CreditCardTransaction__c purchase = dollarPurchase(null);
      // 103 BRL would be inside 5 % of the rate-derived value, yet the pair cannot be confirmed.
      AXF_OBJ_Entry__c reais = entry(103, 'BRL');
      AXF_OBJ_Entry__c dollars = entry(20, 'USD');
      System.assertEquals(0, suggest().size());
      for (
        AXF_OBJ_Entry__c candidate : new List<AXF_OBJ_Entry__c>{
          reais,
          dollars
        }
      ) {
        ALT_CLS_Reconciliation.Outcome outcome = reconcile(candidate, purchase);
        System.assertEquals(false, outcome.success);
        System.assert(outcome.message.contains('moeda estrangeira'));
        System.assertEquals(
          'Pending',
          reload(candidate.Id).AXF_ENT_PKL_Status__c
        );
      }
      System.assertNotEquals(
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
  static void toleranceIsFivePercentOfTheInvoiceBrl() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      dollarPurchase(-100);
      AXF_OBJ_Entry__c inside = entry(104.9, 'BRL');
      System.assertEquals(1, suggest().size());
      delete inside;
      AXF_OBJ_Entry__c outside = entry(105.2, 'BRL');
      System.assertEquals(0, suggest().size());
      delete outside;
      entry(95.1, 'BRL');
      System.assertEquals(1, suggest().size());
    }
  }

  @IsTest
  static void dollarEntryNeedsTheSameDollarAmount() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      dollarPurchase(-105.5);
      entry(20.5, 'USD');
      System.assertEquals(0, suggest().size());
    }
  }

  @IsTest
  static void foreignGuardFallsBackToTheRecordCurrency() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_CreditCardTransaction__c purchase = new AXF_OBJ_CreditCardTransaction__c(
        AXF_CCT_MD_CreditCard__c = card.Id,
        AXF_CCT_LKP_Invoice__c = invoice.Id,
        AXF_CCT_DAT_Date__c = DAY,
        AXF_CCT_CUR_Amount__c = -20,
        CurrencyIsoCode = 'USD'
      );
      insert purchase;
      ALT_CLS_Reconciliation.Outcome outcome = reconcile(
        entry(20, 'USD'),
        purchase
      );
      System.assertEquals(false, outcome.success);
      System.assert(outcome.message.contains('moeda estrangeira'));
    }
  }

  @IsTest
  static void createdEntryIsAnExpenseRealizedAndLinked() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_CreditCardTransaction__c purchase = dollarPurchase(-105.5);
      ALT_CLS_ReconciliationActions.Outcome outcome = new ALT_CLS_ReconciliationActions()
        .createEntries(null, new List<Id>{ purchase.Id })[0];
      AXF_OBJ_Entry__c created = [
        SELECT
          AXF_ENT_PKL_Type__c,
          AXF_ENT_PKL_Status__c,
          AXF_ENT_LKP_CreditCardTransaction__c
        FROM AXF_OBJ_Entry__c
        WHERE Id = :outcome.entryId
      ];
      System.assertEquals('Expense', created.AXF_ENT_PKL_Type__c);
      System.assertEquals('Realized', created.AXF_ENT_PKL_Status__c);
      System.assertEquals(
        purchase.Id,
        created.AXF_ENT_LKP_CreditCardTransaction__c
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
  static void createdEntryKeepsTheDollarAmountAndTheBrlRealizedValue() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_OBJ_CreditCardTransaction__c purchase = dollarPurchase(-105.5);
      ALT_CLS_ReconciliationActions.Outcome outcome = new ALT_CLS_ReconciliationActions()
        .createEntries(null, new List<Id>{ purchase.Id })[0];
      System.assertEquals(true, outcome.success, '' + outcome.message);
      AXF_OBJ_Entry__c created = reload(outcome.entryId);
      System.assertEquals('USD', created.CurrencyIsoCode);
      System.assertEquals(20, created.AXF_ENT_CUR_Amount__c);
      System.assertEquals(105.5, created.AXF_ENT_NUM_RealizedAmountBRL__c);
    }
  }
}
