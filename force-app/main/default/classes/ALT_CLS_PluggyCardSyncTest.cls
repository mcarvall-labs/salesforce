@IsTest
private class ALT_CLS_PluggyCardSyncTest {
  private class PluggyMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String url = req.getEndpoint();
      if (url.endsWith('/auth')) {
        res.setBody('{"apiKey":"abc"}');
      } else if (url.contains('/bills?accountId=card-1')) {
        res.setBody(
          '{"total":1,"totalPages":1,"page":1,"results":[{"id":"bill-1","dueDate":"2026-10-05T00:00:00.000Z","totalAmount":1234.56}]}'
        );
      } else {
        System.assert(
          url.contains('/v2/transactions?accountId=card-1&dateFrom=')
        );
        res.setBody(
          '{"results":[' +
            '{"id":"ct-1","amount":-50,"type":"DEBIT","date":"2026-09-10T00:00:00.000Z","description":"Loja","currencyCode":"USD","amountInAccountCurrency":-260.25,"creditCardMetadata":{"billId":"bill-1","installmentNumber":3,"totalInstallments":10}},' +
            '{"id":"ct-2","amount":20,"type":"CREDIT","date":"2026-09-11T00:00:00.000Z","description":"Estorno","currencyCode":"BRL","creditCardMetadata":{"billId":"unknown"}}' +
            '],"next":null}'
        );
      }
      return res;
    }
  }

  private class ErrorMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(req.getEndpoint().endsWith('/auth') ? 200 : 500);
      res.setBody('{"apiKey":"abc"}');
      return res;
    }
  }

  @TestSetup
  static void setup() {
    ALT_CLS_SyncTestUser.create(
      'axfcs',
      new List<String>{
        'AXF_OBJ_CreditCard__c',
        'AXF_OBJ_CreditCardInvoice__c',
        'AXF_OBJ_CreditCardTransaction__c',
        'AXF_OBJ_Entry__c'
      }
    );
  }

  private static AXF_OBJ_CreditCard__c card(String pluggyId) {
    Account holder = new Account(Name = 'Holder');
    insert holder;
    AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
      Name = 'Cartão',
      AXF_CC_MD_Holder__c = holder.Id,
      AXF_CC_PKL_Institution__c = '341',
      AXF_CC_EXI_PluggyCardId__c = pluggyId
    );
    insert card;
    return card;
  }

  @IsTest
  static void syncCreatesInvoicesAndLinksTransactions() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_CreditCard__c card = card('card-1');
      Test.setMock(HttpCalloutMock.class, new PluggyMock());
      Test.startTest();
      ALT_CLS_PluggyCardSync.Result r = new ALT_CLS_PluggyCardSync()
        .sync(card.Id);
      Test.stopTest();
      System.assertEquals(true, r.success, r.message);
      System.assertEquals(1, r.invoices);
      System.assertEquals(2, r.transactions);
      AXF_OBJ_CreditCardInvoice__c invoice = [
        SELECT
          AXF_CCI_TXT_Period__c,
          AXF_CCI_DAT_DueDate__c,
          AXF_CCI_CUR_TotalAmount__c,
          AXF_CCI_PKL_Status__c
        FROM AXF_OBJ_CreditCardInvoice__c
      ];
      System.assertEquals('2026-10', invoice.AXF_CCI_TXT_Period__c);
      System.assertEquals(
        Date.newInstance(2026, 10, 5),
        invoice.AXF_CCI_DAT_DueDate__c
      );
      System.assertEquals(1234.56, invoice.AXF_CCI_CUR_TotalAmount__c);
      AXF_OBJ_CreditCardTransaction__c linked = [
        SELECT
          AXF_CCT_CUR_Amount__c,
          AXF_CCT_CUR_AmountBRL__c,
          AXF_CCT_TXT_CurrencyCode__c,
          AXF_CCT_TXT_Installment__c,
          AXF_CCT_LKP_Invoice__c
        FROM AXF_OBJ_CreditCardTransaction__c
        WHERE AXF_CCT_EXI_PluggyTransactionId__c = 'ct-1'
      ];
      System.assertEquals(-50, linked.AXF_CCT_CUR_Amount__c);
      System.assertEquals(-260.25, linked.AXF_CCT_CUR_AmountBRL__c);
      System.assertEquals('USD', linked.AXF_CCT_TXT_CurrencyCode__c);
      System.assertEquals('3/10', linked.AXF_CCT_TXT_Installment__c);
      System.assertEquals(
        [SELECT Id FROM AXF_OBJ_CreditCardInvoice__c].Id,
        linked.AXF_CCT_LKP_Invoice__c
      );
      AXF_OBJ_CreditCardTransaction__c refund = [
        SELECT AXF_CCT_CUR_Amount__c, AXF_CCT_LKP_Invoice__c
        FROM AXF_OBJ_CreditCardTransaction__c
        WHERE AXF_CCT_EXI_PluggyTransactionId__c = 'ct-2'
      ];
      System.assertEquals(20, refund.AXF_CCT_CUR_Amount__c);
      System.assertEquals(null, refund.AXF_CCT_LKP_Invoice__c);
    }
  }

  @IsTest
  static void syncUpdatesExistingRecordsWithoutDuplicates() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_CreditCard__c card = card('card-1');
      insert new AXF_OBJ_CreditCardInvoice__c(
        AXF_CCI_MD_CreditCard__c = card.Id,
        AXF_CCI_TXT_Period__c = '2026-09',
        AXF_CCI_PKL_Status__c = 'Open',
        AXF_CCI_EXI_PluggyInvoiceId__c = 'bill-1'
      );
      Test.setMock(HttpCalloutMock.class, new PluggyMock());
      Test.startTest();
      ALT_CLS_PluggyCardSync.Result r = new ALT_CLS_PluggyCardSync()
        .sync(card.Id);
      Test.stopTest();
      System.assertEquals(true, r.success, r.message);
      System.assertEquals(
        1,
        [SELECT COUNT() FROM AXF_OBJ_CreditCardInvoice__c]
      );
      System.assertEquals(
        '2026-10',
        [SELECT AXF_CCI_TXT_Period__c FROM AXF_OBJ_CreditCardInvoice__c]
        .AXF_CCI_TXT_Period__c
      );
    }
  }

  @IsTest
  static void syncRejectsManualCard() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_CreditCard__c card = card(null);
      System.assertEquals(
        false,
        new ALT_CLS_PluggyCardSync().sync(card.Id).success
      );
    }
  }

  @IsTest
  static void syncReportsPluggyError() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_CreditCard__c card = card('card-1');
      Test.setMock(HttpCalloutMock.class, new ErrorMock());
      Test.startTest();
      ALT_CLS_PluggyCardSync.Result r = new ALT_CLS_PluggyCardSync()
        .sync(card.Id);
      Test.stopTest();
      System.assertEquals(false, r.success);
      System.assert(r.message.contains('HTTP 500'));
    }
  }

  private static String firstTransactionsUrl;

  private class OddMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String url = req.getEndpoint();
      if (url.endsWith('/auth')) {
        res.setBody('{"apiKey":"abc"}');
      } else if (url.contains('/bills?accountId=card-1&page=1')) {
        res.setBody(
          '{"totalPages":2,"page":1,"results":[{"id":"bill-1","dueDate":"' +
            String.valueOf(Date.today().addDays(30)) +
            'T00:00:00.000Z","totalAmount":10},{"id":"bill-bad","totalAmount":1}]}'
        );
      } else if (url.contains('/bills?accountId=card-1&page=2')) {
        res.setBody(
          '{"totalPages":2,"page":2,"results":[{"id":"bill-2","dueDate":"2020-01-05T00:00:00.000Z"}]}'
        );
      } else {
        firstTransactionsUrl = url;
        res.setBody(
          '{"results":[' +
            '{"id":"c1","amount":-10,"type":"DEBIT","date":"2026-09-10T00:00:00.000Z","currencyCode":"BRL","creditCardMetadata":{"billId":"bill-2","installmentNumber":2}},' +
            '{"id":"c2","amount":-5,"type":"DEBIT","date":"2026-09-11T00:00:00.000Z","creditCardMetadata":{"billId":"bill-zzz"}},' +
            '{"amount":1}' +
            '],"next":null}'
        );
      }
      return res;
    }
  }

  private class EndlessBillsMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setBody(
        req.getEndpoint().endsWith('/auth')
          ? '{"apiKey":"abc"}'
          : '{"totalPages":99,"results":[]}'
      );
      return res;
    }
  }

  @IsTest
  static void incompleteBillsAreSkippedStatusIsDerivedAndUnlinkedAreCounted() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_CreditCard__c card = card('card-1');
      Test.setMock(HttpCalloutMock.class, new OddMock());
      Test.startTest();
      ALT_CLS_PluggyCardSync.Result r = new ALT_CLS_PluggyCardSync()
        .sync(card.Id);
      Test.stopTest();
      System.assertEquals(true, r.success, r.message);
      System.assertEquals(2, r.invoices);
      System.assertEquals(2, r.skipped);
      System.assertEquals(1, r.withoutInvoice);
      System.assertEquals(
        'Open',
        [
          SELECT AXF_CCI_PKL_Status__c
          FROM AXF_OBJ_CreditCardInvoice__c
          WHERE AXF_CCI_EXI_PluggyInvoiceId__c = 'bill-1'
        ]
        .AXF_CCI_PKL_Status__c
      );
      System.assertEquals(
        'Closed',
        [
          SELECT AXF_CCI_PKL_Status__c
          FROM AXF_OBJ_CreditCardInvoice__c
          WHERE AXF_CCI_EXI_PluggyInvoiceId__c = 'bill-2'
        ]
        .AXF_CCI_PKL_Status__c
      );
      AXF_OBJ_CreditCardTransaction__c c1 = [
        SELECT
          AXF_CCT_TXT_Installment__c,
          AXF_CCT_CUR_AmountBRL__c,
          AXF_CCT_LKP_Invoice__c
        FROM AXF_OBJ_CreditCardTransaction__c
        WHERE AXF_CCT_EXI_PluggyTransactionId__c = 'c1'
      ];
      System.assertEquals('2', c1.AXF_CCT_TXT_Installment__c);
      System.assertEquals(-10, c1.AXF_CCT_CUR_AmountBRL__c);
      System.assertNotEquals(null, c1.AXF_CCT_LKP_Invoice__c);
      System.assert(r.message.contains('sem fatura'));
      System.assert(
        firstTransactionsUrl.endsWith(
          'dateFrom=' + String.valueOf(Date.today().addDays(-90))
        ),
        firstTransactionsUrl
      );
    }
  }

  @IsTest
  static void resyncKeepsAPaidInvoicePaid() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_CreditCard__c card = card('card-1');
      insert new AXF_OBJ_CreditCardInvoice__c(
        AXF_CCI_MD_CreditCard__c = card.Id,
        AXF_CCI_TXT_Period__c = '2020-01',
        AXF_CCI_PKL_Status__c = 'Paid',
        AXF_CCI_EXI_PluggyInvoiceId__c = 'bill-2'
      );
      Test.setMock(HttpCalloutMock.class, new OddMock());
      Test.startTest();
      new ALT_CLS_PluggyCardSync().sync(card.Id);
      Test.stopTest();
      System.assertEquals(
        'Paid',
        [
          SELECT AXF_CCI_PKL_Status__c
          FROM AXF_OBJ_CreditCardInvoice__c
          WHERE AXF_CCI_EXI_PluggyInvoiceId__c = 'bill-2'
        ]
        .AXF_CCI_PKL_Status__c
      );
    }
  }

  @IsTest
  static void billPageCeilingFailsWithoutWriting() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_CreditCard__c card = card('card-1');
      ALT_CLS_PluggyCardSync.maxBillPages = 2;
      Test.setMock(HttpCalloutMock.class, new EndlessBillsMock());
      Test.startTest();
      ALT_CLS_PluggyCardSync.Result r = new ALT_CLS_PluggyCardSync()
        .sync(card.Id);
      Test.stopTest();
      System.assertEquals(false, r.success);
      System.assert(r.message.contains('mais de 2 páginas'));
      System.assertEquals(
        0,
        [SELECT COUNT() FROM AXF_OBJ_CreditCardInvoice__c]
      );
    }
  }

  private static AXF_OBJ_Entry__c invoiceEntry() {
    return [
      SELECT
        Name,
        AXF_ENT_PKL_Type__c,
        AXF_ENT_PKL_Status__c,
        CurrencyIsoCode,
        AXF_ENT_CUR_Amount__c,
        AXF_ENT_DAT_DueDate__c,
        AXF_ENT_LKP_CreditCard__c,
        AXF_ENT_LKP_Invoice__c,
        AXF_ENT_MD_Holder__c
      FROM AXF_OBJ_Entry__c
    ];
  }

  @IsTest
  static void syncCreatesOneExpenseEntryPerInvoiceInBrl() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_CreditCard__c card = card('card-1');
      Test.setMock(HttpCalloutMock.class, new PluggyMock());
      Test.startTest();
      ALT_CLS_PluggyCardSync.Result r = new ALT_CLS_PluggyCardSync()
        .sync(card.Id);
      Test.stopTest();
      System.assertEquals(true, r.success, '' + r.message);
      System.assertEquals(1, r.invoiceEntries);
      AXF_OBJ_Entry__c entry = invoiceEntry();
      System.assertEquals('Expense', entry.AXF_ENT_PKL_Type__c);
      System.assertEquals('Pending', entry.AXF_ENT_PKL_Status__c);
      System.assertEquals('BRL', entry.CurrencyIsoCode);
      System.assertEquals(1234.56, entry.AXF_ENT_CUR_Amount__c);
      System.assertEquals(
        Date.newInstance(2026, 10, 5),
        entry.AXF_ENT_DAT_DueDate__c
      );
      System.assertEquals(card.Id, entry.AXF_ENT_LKP_CreditCard__c);
      System.assertEquals(
        [SELECT Id FROM AXF_OBJ_CreditCardInvoice__c].Id,
        entry.AXF_ENT_LKP_Invoice__c
      );
      System.assertEquals(
        [SELECT AXF_CC_MD_Holder__c FROM AXF_OBJ_CreditCard__c]
        .AXF_CC_MD_Holder__c,
        entry.AXF_ENT_MD_Holder__c
      );
      System.assert(entry.Name.contains('2026-10'));
    }
  }

  // Invoice with the Pluggy id of the mocked bill plus an Entry on it, set up before the callout.
  private static AXF_OBJ_Entry__c entryOnExistingInvoice(
    AXF_OBJ_CreditCard__c card,
    String status
  ) {
    AXF_OBJ_CreditCardInvoice__c invoice = new AXF_OBJ_CreditCardInvoice__c(
      AXF_CCI_MD_CreditCard__c = card.Id,
      AXF_CCI_TXT_Period__c = '2026-10',
      AXF_CCI_PKL_Status__c = 'Open',
      AXF_CCI_EXI_PluggyInvoiceId__c = 'bill-1'
    );
    insert invoice;
    AXF_OBJ_Entry__c entry = new AXF_OBJ_Entry__c(
      Name = 'Fatura',
      AXF_ENT_MD_Holder__c = card.AXF_CC_MD_Holder__c,
      AXF_ENT_PKL_Type__c = 'Expense',
      AXF_ENT_PKL_Status__c = status,
      AXF_ENT_DAT_PaymentDate__c = status == 'Realized'
        ? Date.newInstance(2026, 10, 4)
        : null,
      AXF_ENT_CUR_Amount__c = 1000,
      AXF_ENT_DAT_DueDate__c = Date.newInstance(2026, 1, 1),
      AXF_ENT_LKP_CreditCard__c = card.Id,
      AXF_ENT_LKP_Invoice__c = invoice.Id
    );
    insert entry;
    return entry;
  }

  @IsTest
  static void syncRefreshesThePendingEntryWithoutDuplicating() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_CreditCard__c card = card('card-1');
      entryOnExistingInvoice(card, 'Pending');
      Test.setMock(HttpCalloutMock.class, new PluggyMock());
      Test.startTest();
      ALT_CLS_PluggyCardSync.Result r = new ALT_CLS_PluggyCardSync()
        .sync(card.Id);
      Test.stopTest();
      System.assertEquals(true, r.success, '' + r.message);
      System.assertEquals(1, r.invoiceEntries);
      System.assertEquals(1, [SELECT COUNT() FROM AXF_OBJ_Entry__c]);
      AXF_OBJ_Entry__c refreshed = invoiceEntry();
      System.assertEquals(1234.56, refreshed.AXF_ENT_CUR_Amount__c);
      System.assertEquals(
        Date.newInstance(2026, 10, 5),
        refreshed.AXF_ENT_DAT_DueDate__c
      );
    }
  }

  @IsTest
  static void realizedInvoiceEntryIsLeftAlone() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_CreditCard__c card = card('card-1');
      entryOnExistingInvoice(card, 'Realized');
      Test.setMock(HttpCalloutMock.class, new PluggyMock());
      Test.startTest();
      ALT_CLS_PluggyCardSync.Result r = new ALT_CLS_PluggyCardSync()
        .sync(card.Id);
      Test.stopTest();
      System.assertEquals(true, r.success, '' + r.message);
      System.assertEquals(0, r.invoiceEntries);
      AXF_OBJ_Entry__c untouched = invoiceEntry();
      System.assertEquals(1000, untouched.AXF_ENT_CUR_Amount__c);
      System.assertEquals(
        Date.newInstance(2026, 1, 1),
        untouched.AXF_ENT_DAT_DueDate__c
      );
    }
  }
}
