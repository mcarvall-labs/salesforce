@IsTest
private class AXF_CLS_PluggyBankAccSyncQueueableTest {
  private static final String ACC_OK = AXF_CLS_PluggyTestFactory.BANK_PLUGGY_ID;
  private static final String ACC_LIMITED = 'acc-bank-limited';
  private static final String ACC_BROKEN = 'acc-bank-broken';

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
      AXF_OBJ_BankAccount__c limited = AXF_CLS_PluggyTestFactory.createBankAccount(
        conn.Id,
        null,
        ACC_LIMITED
      );
      limited.AXF_BA_DT_LastTransactionSync__c = Datetime.newInstance(
        2026,
        9,
        1
      );
      update limited;
      AXF_CLS_PluggyTestFactory.createBankAccount(conn.Id, null, ACC_BROKEN);
      // Account without a connection is skipped entirely
      AXF_CLS_PluggyTestFactory.createBankAccount(
        null,
        null,
        'acc-no-connection'
      );
    }
  }

  private static String page(String txId, String accountId) {
    return AXF_CLS_PluggyTestFactory.txBody(
      new List<Object>{
        AXF_CLS_PluggyTestFactory.txJson(txId, accountId, -50.00, null)
      },
      null
    );
  }

  private static Map<String, AXF_OBJ_BankAccount__c> accountsByPluggyId() {
    Map<String, AXF_OBJ_BankAccount__c> result = new Map<String, AXF_OBJ_BankAccount__c>();
    for (AXF_OBJ_BankAccount__c ba : [
      SELECT AXF_BA_EXI_PluggyAccountId__c, AXF_BA_DT_LastTransactionSync__c
      FROM AXF_OBJ_BankAccount__c
    ]) {
      result.put(ba.AXF_BA_EXI_PluggyAccountId__c, ba);
    }
    return result;
  }

  @IsTest
  static void syncsTransactionsAndStampsLastSync() {
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody())
      .route('accountId=' + ACC_OK, 200, page('tx-ok', ACC_OK))
      .route('accountId=' + ACC_LIMITED, 200, page('tx-limited', ACC_LIMITED))
      .onThrow('accountId=' + ACC_BROKEN);
    Test.setMock(HttpCalloutMock.class, mock);

    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      System.enqueueJob(new AXF_CLS_PluggyBankAccountSyncQueueable());
      Test.stopTest();
    }

    Assert.areEqual(2, [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c]);
    Map<String, AXF_OBJ_BankAccount__c> accounts = accountsByPluggyId();
    Assert.isNotNull(accounts.get(ACC_OK).AXF_BA_DT_LastTransactionSync__c);
    Assert.isTrue(
      accounts.get(ACC_LIMITED).AXF_BA_DT_LastTransactionSync__c >
      Datetime.newInstance(2026, 9, 1)
    );
    Assert.isNull(
      accounts.get(ACC_BROKEN).AXF_BA_DT_LastTransactionSync__c,
      'Failed account is not stamped'
    );
    Assert.isNull(
      accounts.get('acc-no-connection').AXF_BA_DT_LastTransactionSync__c
    );

    String incremental;
    for (String e : mock.endpoints) {
      if (e.contains(ACC_LIMITED)) {
        incremental = e;
      }
    }
    Assert.isTrue(
      incremental.contains('dateFrom=2026-09-01'),
      'Incremental sync starts at last sync: ' + incremental
    );
  }

  @IsTest
  static void rateLimitPersistsPagesFetchedBeforeInterruption() {
    AXF_OBJ_BankAccount__c limited = [
      SELECT Id
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_EXI_PluggyAccountId__c = :ACC_LIMITED
    ];
    String resumedPage = AXF_CLS_PluggyTestFactory.txBody(
      new List<Object>{
        AXF_CLS_PluggyTestFactory.txJson(
          'tx-limited',
          ACC_LIMITED,
          -50.00,
          null
        )
      },
      'cursor-10'
    );
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody())
      .onWithHeader('after=cursor-10', 429, '{}', 'Retry-After', '20')
      .route('after=cursor-9', 200, resumedPage);
    Test.setMock(HttpCalloutMock.class, mock);

    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      // Resume constructor: the rate-limited account resumes from the given cursor
      System.enqueueJob(
        new AXF_CLS_PluggyBankAccountSyncQueueable(
          new List<AXF_OBJ_BankAccount__c>{ limited },
          limited.Id,
          'cursor-9',
          1
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
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE AXF_BAT_EXI_PluggyTransactionId__c = 'tx-limited'
      ],
      'Page fetched before the 429 must be persisted'
    );
    Assert.areEqual(
      Datetime.newInstance(2026, 9, 1),
      accountsByPluggyId().get(ACC_LIMITED).AXF_BA_DT_LastTransactionSync__c,
      'Interrupted account keeps its previous last sync'
    );
  }

  @IsTest
  static void rateLimitOnSecondAccountKeepsFirstAccountStamp() {
    List<AXF_OBJ_BankAccount__c> pair = [
      SELECT Id
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_EXI_PluggyAccountId__c IN (:ACC_OK, :ACC_LIMITED)
    ];
    // Whichever account is processed first succeeds; the second one is rate limited.
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody())
      .routeOnce('/v2/transactions', 200, page('tx-first', ACC_OK))
      .route('/v2/transactions', 429, '{}');
    Test.setMock(HttpCalloutMock.class, mock);

    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      System.enqueueJob(new AXF_CLS_PluggyBankAccountSyncQueueable(pair));
      Test.stopTest();
    }

    Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c]);
    Integer stamped = 0;
    for (AXF_OBJ_BankAccount__c ba : accountsByPluggyId().values()) {
      if (
        ba.AXF_BA_DT_LastTransactionSync__c != null &&
        ba.AXF_BA_DT_LastTransactionSync__c > Datetime.newInstance(2026, 9, 2)
      ) {
        stamped++;
      }
    }
    Assert.areEqual(
      1,
      stamped,
      'Only the account fully synced before the 429 is stamped'
    );
  }

  @IsTest
  static void emptyOrUnsyncableInputDoesNothing() {
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody());
    Test.setMock(HttpCalloutMock.class, mock);
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      // Deleted record: the queueable re-query finds nothing to sync
      AXF_OBJ_BankAccount__c noPluggyId = AXF_CLS_PluggyTestFactory.createBankAccount(
        null,
        null,
        'acc-deleted'
      );
      delete noPluggyId;
      Test.startTest();
      new AXF_CLS_PluggyBankAccountSyncQueueable(
          new List<AXF_OBJ_BankAccount__c>()
        )
        .execute(null);
      new AXF_CLS_PluggyBankAccountSyncQueueable(null).execute(null);
      new AXF_CLS_PluggyBankAccountSyncQueueable(
          new List<AXF_OBJ_BankAccount__c>{ noPluggyId }
        )
        .execute(null);
      Test.stopTest();
    }
    Assert.areEqual(0, mock.endpoints.size());
  }
}
