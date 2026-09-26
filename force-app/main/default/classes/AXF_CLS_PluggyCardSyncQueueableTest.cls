@IsTest
private class AXF_CLS_PluggyCardSyncQueueableTest {
  private static final String CARD_OK = AXF_CLS_PluggyTestFactory.CARD_PLUGGY_ID;
  private static final String CARD_BROKEN = 'acc-card-broken';

  @TestSetup
  static void setup() {
    User u = AXF_CLS_PluggyTestFactory.createTestUser();
    System.runAs(u) {
      AXF_CLS_PluggyTestFactory.createStandardData();
      AXF_OBJ_PluggyConnection__c conn = [
        SELECT Id
        FROM AXF_OBJ_PluggyConnection__c
        LIMIT 1
      ];
      AXF_OBJ_CreditCard__c broken = AXF_CLS_PluggyTestFactory.createCreditCard(
        conn.Id,
        CARD_BROKEN,
        '9999'
      );
      broken.AXF_CC_DT_LastTransactionSync__c = Datetime.newInstance(
        2026,
        9,
        1
      );
      update broken;
      AXF_CLS_PluggyTestFactory.createCreditCard(
        null,
        'acc-card-no-connection',
        '5555'
      );
      AXF_OBJ_CreditCard__c ok = [
        SELECT Id
        FROM AXF_OBJ_CreditCard__c
        WHERE AXF_CC_EXI_PluggyCreditCardId__c = :CARD_OK
      ];
      AXF_CLS_PluggyTestFactory.createInvoice(ok.Id, 'bill-001', null);
    }
  }

  private static Map<String, AXF_OBJ_CreditCard__c> cardsByPluggyId() {
    Map<String, AXF_OBJ_CreditCard__c> result = new Map<String, AXF_OBJ_CreditCard__c>();
    for (AXF_OBJ_CreditCard__c c : [
      SELECT
        Id,
        AXF_CC_EXI_PluggyCreditCardId__c,
        AXF_CC_DT_LastTransactionSync__c
      FROM AXF_OBJ_CreditCard__c
    ]) {
      result.put(c.AXF_CC_EXI_PluggyCreditCardId__c, c);
    }
    return result;
  }

  @IsTest
  static void billsPhaseUpsertsInvoices() {
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody())
      .onThrow('/bills?accountId=' + CARD_BROKEN)
      .route(
        '/bills?accountId=' + CARD_OK,
        200,
        AXF_CLS_PluggyTestFactory.billsBody()
      )
      .route('/bills', 200, '{"results":[]}');
    Test.setMock(HttpCalloutMock.class, mock);

    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      System.enqueueJob(new AXF_CLS_PluggyCreditCardSyncQueueable());
      Test.stopTest();
    }

    Assert.areEqual(
      3,
      mock.callsTo('/bills'),
      'One bills callout per card with a Pluggy id'
    );
    Assert.areEqual(
      0,
      mock.callsTo('/v2/transactions'),
      'Transactions run in a separate phase'
    );
    AXF_OBJ_CreditCardInvoice__c updated = [
      SELECT AXF_CCI_CUR_TotalAmount__c, AXF_CCI_TXT_Period__c
      FROM AXF_OBJ_CreditCardInvoice__c
      WHERE AXF_CCI_EXI_PluggyInvoiceId__c = 'bill-001'
    ];
    Assert.areEqual(
      850.40,
      updated.AXF_CCI_CUR_TotalAmount__c,
      'Existing invoice updated by external id'
    );
    Assert.areEqual(2, [SELECT COUNT() FROM AXF_OBJ_CreditCardInvoice__c]);
  }

  @IsTest
  static void transactionsPhaseUpsertsAndStampsCards() {
    String okPage = AXF_CLS_PluggyTestFactory.txBody(
      new List<Object>{
        AXF_CLS_PluggyTestFactory.txJson(
          'tx-card-ok',
          CARD_OK,
          -99.90,
          'bill-001'
        )
      },
      null
    );
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody())
      .onThrow('accountId=' + CARD_BROKEN)
      .route('accountId=' + CARD_OK, 200, okPage);
    Test.setMock(HttpCalloutMock.class, mock);
    List<AXF_OBJ_CreditCard__c> cards = [SELECT Id FROM AXF_OBJ_CreditCard__c];

    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      System.enqueueJob(
        new AXF_CLS_PluggyCreditCardSyncQueueable(
          cards,
          AXF_CLS_PluggyCreditCardSyncQueueable.SyncPhase.TRANSACTIONS
        )
      );
      Test.stopTest();
    }

    AXF_OBJ_CreditCardTransaction__c tx = [
      SELECT
        AXF_CCT_CUR_Amount__c,
        AXF_CCT_LKP_CreditCardInvoice__r.AXF_CCI_EXI_PluggyInvoiceId__c
      FROM AXF_OBJ_CreditCardTransaction__c
    ];
    Assert.areEqual(-99.90, tx.AXF_CCT_CUR_Amount__c);
    Assert.areEqual(
      'bill-001',
      tx.AXF_CCT_LKP_CreditCardInvoice__r.AXF_CCI_EXI_PluggyInvoiceId__c
    );
    Map<String, AXF_OBJ_CreditCard__c> byId = cardsByPluggyId();
    Assert.isNotNull(byId.get(CARD_OK).AXF_CC_DT_LastTransactionSync__c);
    Assert.areEqual(
      Datetime.newInstance(2026, 9, 1),
      byId.get(CARD_BROKEN).AXF_CC_DT_LastTransactionSync__c,
      'Failed card not stamped'
    );
    Assert.isNull(
      byId.get('acc-card-no-connection').AXF_CC_DT_LastTransactionSync__c
    );
    Assert.areEqual(0, mock.callsTo('/bills'));
  }

  @IsTest
  static void rateLimitPersistsPagesFetchedBeforeInterruption() {
    AXF_OBJ_CreditCard__c card = cardsByPluggyId().get(CARD_OK);
    String resumedPage = AXF_CLS_PluggyTestFactory.txBody(
      new List<Object>{
        AXF_CLS_PluggyTestFactory.txJson(
          'tx-card-partial',
          CARD_OK,
          -10.00,
          'bill-001'
        )
      },
      'cursor-2'
    );
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody())
      .route('after=cursor-2', 429, '{}')
      .route('after=cursor-1', 200, resumedPage);
    Test.setMock(HttpCalloutMock.class, mock);

    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      System.enqueueJob(
        new AXF_CLS_PluggyCreditCardSyncQueueable(
          new List<AXF_OBJ_CreditCard__c>{ card },
          AXF_CLS_PluggyCreditCardSyncQueueable.SyncPhase.TRANSACTIONS,
          card.Id,
          'cursor-1',
          2
        )
      );
      Test.stopTest();
    }

    Assert.areEqual(
      3,
      mock.endpoints.size(),
      'auth + resumed page + rate-limited page'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_CreditCardTransaction__c
        WHERE AXF_CCT_EXI_PluggyTransactionId__c = 'tx-card-partial'
      ]
    );
    Assert.isNull(
      cardsByPluggyId().get(CARD_OK).AXF_CC_DT_LastTransactionSync__c,
      'Interrupted card is not stamped'
    );
  }

  @IsTest
  static void emptyOrUnsyncableInputDoesNothing() {
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody());
    Test.setMock(HttpCalloutMock.class, mock);
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      // Deleted record: the queueable re-query finds nothing to sync
      AXF_OBJ_CreditCard__c manual = AXF_CLS_PluggyTestFactory.createCreditCard(
        null,
        'acc-card-deleted',
        null
      );
      delete manual;
      Test.startTest();
      new AXF_CLS_PluggyCreditCardSyncQueueable(
          new List<AXF_OBJ_CreditCard__c>()
        )
        .execute(null);
      new AXF_CLS_PluggyCreditCardSyncQueueable(null).execute(null);
      new AXF_CLS_PluggyCreditCardSyncQueueable(
          new List<AXF_OBJ_CreditCard__c>{ manual }
        )
        .execute(null);
      Test.stopTest();
    }
    Assert.areEqual(0, mock.endpoints.size());
  }
}
