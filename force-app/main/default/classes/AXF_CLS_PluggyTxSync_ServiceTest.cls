@IsTest
private class AXF_CLS_PluggyTxSync_ServiceTest {
  private static final String BANK = AXF_CLS_PluggyTestFactory.BANK_PLUGGY_ID;
  private static final String CARD = AXF_CLS_PluggyTestFactory.CARD_PLUGGY_ID;

  @TestSetup
  static void setup() {
    User u = AXF_CLS_PluggyTestFactory.createTestUser();
    System.runAs(u) {
      AXF_CLS_PluggyTestFactory.createStandardData();
      AXF_OBJ_CreditCard__c card = [
        SELECT Id
        FROM AXF_OBJ_CreditCard__c
        LIMIT 1
      ];
      AXF_CLS_PluggyTestFactory.createInvoice(
        card.Id,
        'bill-001',
        'bill-001-ext'
      );
      insert new AXF_OBJ_Category__c(
        Name = 'Renda',
        AXF_CAT_EXI_PluggyCategoryId__c = '01000000'
      );
    }
  }

  @IsTest
  static void paginatesRoutesAndUpsertsBankAndCardTransactions() {
    String page1 = AXF_CLS_PluggyTestFactory.txBody(
      new List<Object>{
        AXF_CLS_PluggyTestFactory.txJson('tx-bank-1', BANK, -120.50, null),
        AXF_CLS_PluggyTestFactory.txJson('tx-card-1', CARD, -80.00, 'bill-001'),
        new Map<String, Object>{ 'id' => 'tx-orphan', 'amount' => 1.0 },
        AXF_CLS_PluggyTestFactory.txJson('tx-unknown', 'acc-unknown', 5.0, null)
      },
      'cursor-2'
    );
    String page2 = AXF_CLS_PluggyTestFactory.txBody(
      new List<Object>{
        AXF_CLS_PluggyTestFactory.txJson('tx-bank-2', BANK, 300.00, null)
      },
      null
    );
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('after=cursor-2', 200, page2)
      .route('/v2/transactions?accountId=', 200, page1);
    Test.setMock(HttpCalloutMock.class, mock);

    AXF_CLS_PluggyTxSync_Service.TransactionSyncResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = AXF_CLS_PluggyTxSync_Service.fetchTransactionsForConnection(
        AXF_CLS_PluggyTestFactory.ITEM_ID,
        'key',
        BANK,
        Date.newInstance(2026, 9, 1),
        Date.newInstance(2026, 9, 30)
      );
      AXF_CLS_PluggyTxSync_Service.upsertTransactions(result);
      Test.stopTest();
    }

    Assert.areEqual(2, mock.endpoints.size(), 'Two pages expected');
    Assert.isTrue(
      mock.endpoints[0].contains('&dateFrom=2026-09-01&dateTo=2026-09-30'),
      mock.endpoints[0]
    );
    Assert.isTrue(
      mock.endpoints[1].contains('&after=cursor-2'),
      mock.endpoints[1]
    );
    Assert.areEqual(2, result.bankAccountTransactions.size());
    Assert.areEqual(1, result.creditCardTransactions.size());

    AXF_OBJ_BankAccountTransaction__c bat = [
      SELECT
        AXF_BAT_CUR_Amount__c,
        AXF_BAT_LKP_Category__c,
        AXF_BAT_TXT_Description__c,
        AXF_BAT_LKP_BankAccount__c
      FROM AXF_OBJ_BankAccountTransaction__c
      WHERE AXF_BAT_EXI_PluggyTransactionId__c = 'tx-bank-1'
    ];
    Assert.areEqual(-120.50, bat.AXF_BAT_CUR_Amount__c);
    Assert.isNotNull(
      bat.AXF_BAT_LKP_Category__c,
      'Category resolved by Pluggy id'
    );
    Assert.areEqual('Compra tx-bank-1', bat.AXF_BAT_TXT_Description__c);
    Assert.areEqual(2, [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c]);

    AXF_OBJ_CreditCardTransaction__c cct = [
      SELECT
        Name,
        AXF_CCT_LKP_CreditCardInvoice__r.AXF_CCI_EXI_PluggyInvoiceId__c,
        AXF_CCT_CUR_Amount__c
      FROM AXF_OBJ_CreditCardTransaction__c
      WHERE AXF_CCT_EXI_PluggyTransactionId__c = 'tx-card-1'
    ];
    Assert.areEqual(
      'bill-001',
      cct.AXF_CCT_LKP_CreditCardInvoice__r.AXF_CCI_EXI_PluggyInvoiceId__c,
      'Linked by billId'
    );
    Assert.areEqual('Compra tx-card-1', cct.Name);
  }

  @IsTest
  static void cardTransactionsResolveInvoiceByExternalReferences() {
    AXF_OBJ_CreditCard__c ccRecord = [
      SELECT Id
      FROM AXF_OBJ_CreditCard__c
      LIMIT 1
    ];
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      AXF_CLS_PluggyTestFactory.createInvoice(ccRecord.Id, 'bill-002', null);
    }
    Map<String, Object> noBill = AXF_CLS_PluggyTestFactory.txJson(
      'tx-card-fallback',
      CARD,
      -10.0,
      null
    );
    Map<String, Object> newBill = AXF_CLS_PluggyTestFactory.txJson(
      'tx-card-new-bill',
      CARD,
      -20.0,
      'bill-002'
    );
    newBill.put('description', null);
    String page = AXF_CLS_PluggyTestFactory.txBody(
      new List<Object>{ noBill, newBill },
      null
    );
    Test.setMock(
      HttpCalloutMock.class,
      new AXF_CLS_PluggyTestFactory.MockRouter()
        .route('/v2/transactions', 200, page)
    );

    AXF_CLS_PluggyTxSync_Service.TransactionSyncResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = AXF_CLS_PluggyTxSync_Service.fetchTransactionsForConnection(
        AXF_CLS_PluggyTestFactory.ITEM_ID,
        'key',
        CARD
      );
      Test.stopTest();
    }

    Assert.areEqual(2, result.creditCardTransactions.size());
    AXF_OBJ_CreditCardTransaction__c fallback = result.creditCardTransactions[0];
    Assert.isNull(fallback.AXF_CCT_LKP_CreditCardInvoice__c);
    Assert.isTrue(
      fallback.AXF_CCT_LKP_CreditCardInvoice__r.AXF_CCI_EXT_ExternalId__c.startsWith(
        '1234_2026-09'
      ),
      'Fallback external id is {last four}_{yyyy-MM}'
    );
    AXF_OBJ_CreditCardTransaction__c byBill = result.creditCardTransactions[1];
    Assert.isNotNull(
      byBill.AXF_CCT_LKP_CreditCardInvoice__c,
      'Known billId resolved to the invoice Id'
    );
    Assert.areEqual(
      'Transaction',
      byBill.Name,
      'Blank description falls back to default name'
    );
  }

  @IsTest
  static void unknownBillIdUsesExternalIdReference() {
    Map<String, Object> tx = AXF_CLS_PluggyTestFactory.txJson(
      'tx-card-x',
      CARD,
      -20.0,
      'bill-not-synced'
    );
    Test.setMock(
      HttpCalloutMock.class,
      new AXF_CLS_PluggyTestFactory.MockRouter()
        .route(
          '/v2/transactions',
          200,
          AXF_CLS_PluggyTestFactory.txBody(new List<Object>{ tx }, null)
        )
    );
    AXF_CLS_PluggyTxSync_Service.TransactionSyncResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = AXF_CLS_PluggyTxSync_Service.fetchTransactionsForConnection(
        AXF_CLS_PluggyTestFactory.ITEM_ID,
        'key',
        CARD,
        (String) null
      );
      Test.stopTest();
    }
    Assert.areEqual(
      'bill-not-synced',
      result.creditCardTransactions[0]
        .AXF_CCT_LKP_CreditCardInvoice__r.AXF_CCI_EXI_PluggyInvoiceId__c
    );
  }

  @IsTest
  static void rateLimitCarriesCursorRetryAfterAndPartialResult() {
    String page1 = AXF_CLS_PluggyTestFactory.txBody(
      new List<Object>{
        AXF_CLS_PluggyTestFactory.txJson('tx-bank-1', BANK, 10.0, null)
      },
      'cursor-2'
    );
    Test.setMock(
      HttpCalloutMock.class,
      new AXF_CLS_PluggyTestFactory.MockRouter()
        .onWithHeader(
          'after=cursor-2',
          429,
          '{"message":"rate limited"}',
          'Retry-After',
          '30'
        )
        .route('/v2/transactions', 200, page1)
    );
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      try {
        AXF_CLS_PluggyTxSync_Service.fetchTransactionsForConnection(
          AXF_CLS_PluggyTestFactory.ITEM_ID,
          'key',
          BANK
        );
        Assert.fail('Expected RateLimitException');
      } catch (AXF_CLS_PluggyTxSync_Service.RateLimitException rle) {
        Assert.areEqual('cursor-2', rle.resumeCursor);
        Assert.areEqual(30, rle.retryAfterSeconds);
        Assert.areEqual(
          1,
          rle.partialResult.bankAccountTransactions.size(),
          'Page 1 must not be discarded'
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void rateLimitWithoutNumericRetryAfterFallsBackToNull() {
    Test.setMock(
      HttpCalloutMock.class,
      new AXF_CLS_PluggyTestFactory.MockRouter()
        .onWithHeader(
          '/v2/transactions',
          429,
          '{}',
          'Retry-After',
          'Wed, 21 Oct 2026 07:28:00 GMT'
        )
    );
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      try {
        AXF_CLS_PluggyTxSync_Service.fetchTransactionsForConnection(
          AXF_CLS_PluggyTestFactory.ITEM_ID,
          'key',
          BANK,
          'start-cursor'
        );
        Assert.fail('Expected RateLimitException');
      } catch (AXF_CLS_PluggyTxSync_Service.RateLimitException rle) {
        Assert.areEqual('start-cursor', rle.resumeCursor);
        Assert.isNull(rle.retryAfterSeconds);
        Assert.isTrue(rle.partialResult.bankAccountTransactions.isEmpty());
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void pausesBeforeHittingCalloutGovernorLimit() {
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route(
        '/v2/transactions',
        200,
        AXF_CLS_PluggyTestFactory.txBody(new List<Object>(), 'endless')
      );
    Test.setMock(HttpCalloutMock.class, mock);
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      try {
        AXF_CLS_PluggyTxSync_Service.fetchTransactionsForConnection(
          AXF_CLS_PluggyTestFactory.ITEM_ID,
          'key',
          BANK
        );
        Assert.fail(
          'Expected RateLimitException from the governor-limit guard'
        );
      } catch (AXF_CLS_PluggyTxSync_Service.RateLimitException rle) {
        Assert.areEqual('endless', rle.resumeCursor);
        Assert.areEqual(10, rle.retryAfterSeconds);
        Assert.isTrue(
          rle.getMessage().contains('governor limit'),
          rle.getMessage()
        );
      }
      Test.stopTest();
    }
    Assert.areEqual(
      Limits.getLimitCallouts() - 3,
      mock.endpoints.size(),
      'Stops with a 3-callout safety margin'
    );
  }

  @IsTest
  static void httpErrorAndBlankAccountReturnEmpty() {
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/v2/transactions', 500, '{}');
    Test.setMock(HttpCalloutMock.class, mock);
    AXF_CLS_PluggyTxSync_Service.TransactionSyncResult errResult;
    AXF_CLS_PluggyTxSync_Service.TransactionSyncResult blankResult;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      errResult = AXF_CLS_PluggyTxSync_Service.fetchTransactionsForConnection(
        AXF_CLS_PluggyTestFactory.ITEM_ID,
        'key',
        BANK
      );
      blankResult = AXF_CLS_PluggyTxSync_Service.fetchTransactionsForConnection(
        AXF_CLS_PluggyTestFactory.ITEM_ID,
        'key',
        ''
      );
      AXF_CLS_PluggyTxSync_Service.upsertTransactions(errResult);
      Test.stopTest();
    }
    Assert.isTrue(errResult.bankAccountTransactions.isEmpty());
    Assert.isTrue(blankResult.creditCardTransactions.isEmpty());
    Assert.areEqual(
      1,
      mock.endpoints.size(),
      'Blank account id must not trigger a callout'
    );
  }
}
