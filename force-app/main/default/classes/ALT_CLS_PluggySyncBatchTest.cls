@IsTest
private class ALT_CLS_PluggySyncBatchTest {
  private class PluggyMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      String url = req.getEndpoint();
      res.setStatusCode(200);
      if (url.endsWith('/auth')) {
        res.setBody('{"apiKey":"abc"}');
      } else if (url.contains('itemId=item-bad')) {
        res.setStatusCode(500);
        res.setBody('{}');
      } else if (url.contains('/accounts?itemId=')) {
        res.setBody(
          '{"results":[{"id":"acc-1","type":"BANK","name":"Conta","number":"1","balance":10},{"id":"card-1","type":"CREDIT","name":"Cartão","number":"5555","creditData":{"brand":"VISA"}}]}'
        );
      } else if (url.contains('/bills?accountId=card-1')) {
        res.setBody(
          '{"totalPages":1,"results":[{"id":"bill-1","dueDate":"2026-10-05T00:00:00.000Z","totalAmount":9}]}'
        );
      } else if (url.contains('accountId=card-1')) {
        res.setBody(
          '{"results":[{"id":"ct-1","amount":-9,"type":"DEBIT","date":"2026-09-10T00:00:00.000Z","creditCardMetadata":{"billId":"bill-1"}}],"next":null}'
        );
      } else {
        res.setBody(
          '{"results":[{"id":"tx-1","amount":-5,"type":"DEBIT","date":"2026-09-10T00:00:00.000Z","description":"Cafe"}],"next":null}'
        );
      }
      return res;
    }
  }

  private static AXF_OBJ_PluggyConnection__c connection(
    String item,
    String status
  ) {
    Account holder = new Account(Name = 'Holder ' + item);
    insert holder;
    AXF_OBJ_PluggyConnection__c connection = new AXF_OBJ_PluggyConnection__c(
      AXF_CON_MD_Holder__c = holder.Id,
      AXF_CON_PKL_Institution__c = '341',
      AXF_CON_EXI_PluggyItemId__c = item,
      AXF_CON_PKL_Status__c = status
    );
    insert connection;
    return connection;
  }

  @TestSetup
  static void setup() {
    ALT_CLS_SyncTestUser.create(
      'axfbat',
      new List<String>{
        'AXF_OBJ_PluggyConnection__c',
        'AXF_OBJ_BankAccount__c',
        'AXF_OBJ_BankAccountTransaction__c',
        'AXF_OBJ_CreditCard__c',
        'AXF_OBJ_CreditCardInvoice__c',
        'AXF_OBJ_CreditCardTransaction__c'
      }
    );
  }

  private static ALT_CLS_PluggySyncBatch phase(
    Integer phase,
    Set<Id> attempted,
    Map<Id, String> errors
  ) {
    return new ALT_CLS_PluggySyncBatch(
      null,
      phase,
      attempted,
      errors,
      new Set<Id>()
    );
  }

  private static AXF_OBJ_BankAccount__c bankAccount(
    AXF_OBJ_PluggyConnection__c connection,
    String pluggyId
  ) {
    AXF_OBJ_BankAccount__c account = new AXF_OBJ_BankAccount__c(
      Name = 'Conta',
      AXF_BA_MD_Holder__c = connection.AXF_CON_MD_Holder__c,
      AXF_BA_LKP_Connection__c = connection.Id,
      AXF_BA_PKL_Institution__c = '341',
      AXF_BA_PKL_Type__c = 'Checking',
      AXF_BA_EXI_PluggyAccountId__c = pluggyId
    );
    insert account;
    return account;
  }

  private static AXF_OBJ_CreditCard__c creditCard(
    AXF_OBJ_PluggyConnection__c connection,
    String pluggyId
  ) {
    AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
      Name = 'Cartão',
      AXF_CC_MD_Holder__c = connection.AXF_CON_MD_Holder__c,
      AXF_CC_LKP_Connection__c = connection.Id,
      AXF_CC_PKL_Institution__c = '341',
      AXF_CC_EXI_PluggyCardId__c = pluggyId
    );
    insert card;
    return card;
  }

  private static AXF_OBJ_PluggyConnection__c reload(Id connectionId) {
    return [
      SELECT
        AXF_CON_PKL_Status__c,
        AXF_CON_TAL_SyncErrorMessage__c,
        AXF_CON_DT_LastSyncDatetime__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :connectionId
    ];
  }

  // Runs a locator the way the batch does; its binds only resolve inside the locator.
  private static List<SObject> rows(Database.QueryLocator locator) {
    List<SObject> found = new List<SObject>();
    Database.QueryLocatorIterator iterator = locator.iterator();
    while (iterator.hasNext()) {
      found.add(iterator.next());
    }
    return found;
  }

  // Answers like the Pluggy mock and remembers which accounts were asked for.
  private class RecordingMock implements HttpCalloutMock {
    public List<String> urls = new List<String>();
    public HttpResponse respond(HttpRequest req) {
      urls.add(req.getEndpoint());
      return new PluggyMock().respond(req);
    }
  }

  // Fails every callout of the transaction and invoice endpoints.
  private class FailingMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      if (req.getEndpoint().endsWith('/auth')) {
        res.setStatusCode(200);
        res.setBody('{"apiKey":"abc"}');
      } else {
        res.setStatusCode(500);
        res.setBody('{}');
      }
      return res;
    }
  }

  @IsTest
  static void phasesSyncAccountsTransactionsAndCardsThenRecordTheResult() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_PluggyConnection__c good = connection('item-good', 'Active');
      ALT_CLS_PluggyAccountSync.assignRecordType = false;
      Test.setMock(HttpCalloutMock.class, new PluggyMock());
      Set<Id> attempted = new Set<Id>();
      Map<Id, String> errors = new Map<Id, String>();
      Test.startTest();
      phase(1, attempted, errors).execute(null, new List<SObject>{ good });
      System.assertEquals(new Set<Id>{ good.Id }, attempted);
      System.assertEquals(0, errors.size());
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_BankAccount__c
          WHERE AXF_BA_EXI_PluggyAccountId__c = 'acc-1'
        ]
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void transactionAndCardPhasesFillTheirData() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_PluggyConnection__c good = connection('item-good', 'Active');
      AXF_OBJ_BankAccount__c account = new AXF_OBJ_BankAccount__c(
        Name = 'Conta',
        AXF_BA_MD_Holder__c = good.AXF_CON_MD_Holder__c,
        AXF_BA_LKP_Connection__c = good.Id,
        AXF_BA_PKL_Institution__c = '341',
        AXF_BA_PKL_Type__c = 'Checking',
        AXF_BA_EXI_PluggyAccountId__c = 'acc-1'
      );
      insert account;
      AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
        Name = 'Cartão',
        AXF_CC_MD_Holder__c = good.AXF_CON_MD_Holder__c,
        AXF_CC_LKP_Connection__c = good.Id,
        AXF_CC_PKL_Institution__c = '341',
        AXF_CC_EXI_PluggyCardId__c = 'card-1'
      );
      insert card;
      Test.setMock(HttpCalloutMock.class, new PluggyMock());
      Test.startTest();
      Set<Id> attempted = new Set<Id>{ good.Id };
      phase(2, attempted, new Map<Id, String>())
        .execute(null, new List<SObject>{ account });
      Test.stopTest();
      System.assertEquals(
        1,
        [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c]
      );
    }
  }

  @IsTest
  static void cardPhaseSyncsInvoicesAndTransactions() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_PluggyConnection__c good = connection('item-good', 'Active');
      AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
        Name = 'Cartão',
        AXF_CC_MD_Holder__c = good.AXF_CON_MD_Holder__c,
        AXF_CC_LKP_Connection__c = good.Id,
        AXF_CC_PKL_Institution__c = '341',
        AXF_CC_EXI_PluggyCardId__c = 'card-1'
      );
      insert card;
      Test.setMock(HttpCalloutMock.class, new PluggyMock());
      Test.startTest();
      phase(3, new Set<Id>{ good.Id }, new Map<Id, String>())
        .execute(null, new List<SObject>{ card });
      Test.stopTest();
      System.assertEquals(
        1,
        [SELECT COUNT() FROM AXF_OBJ_CreditCardInvoice__c]
      );
      System.assertEquals(
        1,
        [SELECT COUNT() FROM AXF_OBJ_CreditCardTransaction__c]
      );
    }
  }

  @IsTest
  static void failedConnectionIsMarkedErrorWithTheMessageAndOthersStayActive() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_PluggyConnection__c good = connection('item-good', 'Active');
      AXF_OBJ_PluggyConnection__c bad = connection('item-bad', 'Active');
      ALT_CLS_PluggyAccountSync.assignRecordType = false;
      Test.setMock(HttpCalloutMock.class, new PluggyMock());
      Set<Id> attempted = new Set<Id>();
      Map<Id, String> errors = new Map<Id, String>();
      Test.startTest();
      ALT_CLS_PluggySyncBatch first = phase(1, attempted, errors);
      first.execute(null, new List<SObject>{ bad });
      Test.stopTest();
      System.assertEquals(true, errors.containsKey(bad.Id));
      System.assert(errors.get(bad.Id).contains('HTTP 500'));
      attempted.add(good.Id);
      phase(3, attempted, errors).finish(null);
      AXF_OBJ_PluggyConnection__c savedBad = [
        SELECT AXF_CON_PKL_Status__c, AXF_CON_TAL_SyncErrorMessage__c
        FROM AXF_OBJ_PluggyConnection__c
        WHERE Id = :bad.Id
      ];
      System.assertEquals('Error', savedBad.AXF_CON_PKL_Status__c);
      System.assert(
        savedBad.AXF_CON_TAL_SyncErrorMessage__c.contains('HTTP 500')
      );
      AXF_OBJ_PluggyConnection__c savedGood = [
        SELECT
          AXF_CON_PKL_Status__c,
          AXF_CON_TAL_SyncErrorMessage__c,
          AXF_CON_DT_LastSyncDatetime__c
        FROM AXF_OBJ_PluggyConnection__c
        WHERE Id = :good.Id
      ];
      System.assertEquals('Active', savedGood.AXF_CON_PKL_Status__c);
      System.assertEquals(null, savedGood.AXF_CON_TAL_SyncErrorMessage__c);
      System.assertNotEquals(null, savedGood.AXF_CON_DT_LastSyncDatetime__c);
    }
  }

  @IsTest
  static void aPreviouslyFailedConnectionRecoversAfterASuccessfulRun() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_PluggyConnection__c recovered = connection('item-ok', 'Error');
      update new AXF_OBJ_PluggyConnection__c(
        Id = recovered.Id,
        AXF_CON_TAL_SyncErrorMessage__c = 'old failure'
      );
      phase(3, new Set<Id>{ recovered.Id }, new Map<Id, String>()).finish(null);
      AXF_OBJ_PluggyConnection__c saved = [
        SELECT AXF_CON_PKL_Status__c, AXF_CON_TAL_SyncErrorMessage__c
        FROM AXF_OBJ_PluggyConnection__c
        WHERE Id = :recovered.Id
      ];
      System.assertEquals('Active', saved.AXF_CON_PKL_Status__c);
      System.assertEquals(null, saved.AXF_CON_TAL_SyncErrorMessage__c);
    }
  }

  @IsTest
  static void startPicksOnlyActiveAndErrorConnectionsAndHonorsTheFilter() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_PluggyConnection__c active = connection('item-a', 'Active');
      connection('item-p', 'Paused');
      AXF_OBJ_PluggyConnection__c failed = connection('item-e', 'Error');
      Set<Id> picked = new Map<Id, SObject>(
          rows(new ALT_CLS_PluggySyncBatch(null).start(null))
        )
        .keySet();
      System.assertEquals(new Set<Id>{ active.Id, failed.Id }, picked);
    }
  }

  @IsTest
  static void failuresInAStepAreCaughtAsConnectionErrors() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_PluggyConnection__c good = connection('item-good', 'Active');
      Map<Id, String> errors = new Map<Id, String>();
      Test.startTest();
      // No callout mock: the callout fails and must be recorded, not thrown.
      phase(1, new Set<Id>(), errors).execute(null, new List<SObject>{ good });
      Test.stopTest();
      System.assertEquals(true, errors.containsKey(good.Id));
    }
  }

  @IsTest
  static void firstPhasesChainTheNextOne() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Test.startTest();
      new ALT_CLS_PluggySyncBatch(null).finish(null);
      Test.stopTest();
      System.assert(
        [
          SELECT COUNT()
          FROM AsyncApexJob
          WHERE ApexClass.Name = 'ALT_CLS_PluggySyncBatch'
        ] >= 1
      );
    }
  }

  @IsTest
  static void startOfTheLaterPhasesPicksOnlyTheSyncedConnectionsData() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_PluggyConnection__c good = connection('item-good', 'Active');
      AXF_OBJ_PluggyConnection__c bad = connection('item-bad', 'Active');
      AXF_OBJ_PluggyConnection__c unseen = connection('item-unseen', 'Active');
      bankAccount(good, 'acc-good');
      bankAccount(bad, 'acc-bad');
      bankAccount(unseen, 'acc-unseen');
      creditCard(good, 'card-good');
      creditCard(bad, 'card-bad');
      creditCard(unseen, 'card-unseen');
      Set<Id> attempted = new Set<Id>{ good.Id, bad.Id };
      Map<Id, String> errors = new Map<Id, String>{ bad.Id => 'HTTP 500' };
      // Phase 2: the failed first phase leaves 'bad' out; 'unseen' was never attempted.
      List<SObject> accounts = rows(
        new ALT_CLS_PluggySyncBatch(
            null,
            2,
            attempted,
            errors,
            new Set<Id>{ bad.Id }
          )
          .start(null)
      );
      System.assertEquals(1, accounts.size());
      System.assertEquals(good.Id, accounts[0].get('AXF_BA_LKP_Connection__c'));
      // Phase 3 keeps a connection whose phase 2 failed, and still drops the first-phase failure.
      errors.put(good.Id, 'phase 2 failed');
      List<SObject> cards = rows(
        new ALT_CLS_PluggySyncBatch(
            null,
            3,
            attempted,
            errors,
            new Set<Id>{ bad.Id }
          )
          .start(null)
      );
      System.assertEquals(1, cards.size());
      System.assertEquals(good.Id, cards[0].get('AXF_CC_LKP_Connection__c'));
    }
  }

  @IsTest
  static void startRunsTheFilterAsAQueryForOneConnection() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_PluggyConnection__c first = connection('item-a', 'Active');
      connection('item-b', 'Active');
      List<SObject> picked = rows(
        new ALT_CLS_PluggySyncBatch(first.Id).start(null)
      );
      System.assertEquals(1, picked.size());
      System.assertEquals(first.Id, picked[0].Id);
    }
  }

  @IsTest
  static void failureInTheTransactionPhaseIsRecordedOnItsConnection() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_PluggyConnection__c good = connection('item-good', 'Active');
      AXF_OBJ_BankAccount__c account = bankAccount(good, 'acc-1');
      Map<Id, String> errors = new Map<Id, String>();
      Test.setMock(HttpCalloutMock.class, new FailingMock());
      Test.startTest();
      phase(2, new Set<Id>{ good.Id }, errors)
        .execute(null, new List<SObject>{ account });
      Test.stopTest();
      System.assertEquals(true, errors.containsKey(good.Id));
      phase(3, new Set<Id>{ good.Id }, errors).finish(null);
      AXF_OBJ_PluggyConnection__c saved = reload(good.Id);
      System.assertEquals('Error', saved.AXF_CON_PKL_Status__c);
      System.assertEquals(null, saved.AXF_CON_DT_LastSyncDatetime__c);
      System.assertNotEquals(null, saved.AXF_CON_TAL_SyncErrorMessage__c);
    }
  }

  @IsTest
  static void failureInTheCardPhaseIsRecordedOnItsConnection() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_PluggyConnection__c good = connection('item-good', 'Active');
      AXF_OBJ_CreditCard__c card = creditCard(good, 'card-1');
      Map<Id, String> errors = new Map<Id, String>();
      Test.setMock(HttpCalloutMock.class, new FailingMock());
      Test.startTest();
      phase(3, new Set<Id>{ good.Id }, errors)
        .execute(null, new List<SObject>{ card });
      Test.stopTest();
      System.assertEquals(true, errors.containsKey(good.Id));
      phase(3, new Set<Id>{ good.Id }, errors).finish(null);
      System.assertEquals('Error', reload(good.Id).AXF_CON_PKL_Status__c);
    }
  }

  @IsTest
  static void aDeletedConnectionDoesNotDropTheOthersResult() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_PluggyConnection__c good = connection('item-good', 'Active');
      AXF_OBJ_PluggyConnection__c gone = connection('item-gone', 'Active');
      Set<Id> attempted = new Set<Id>{ good.Id, gone.Id };
      delete gone;
      phase(3, attempted, new Map<Id, String>()).finish(null);
      AXF_OBJ_PluggyConnection__c saved = reload(good.Id);
      System.assertEquals('Active', saved.AXF_CON_PKL_Status__c);
      System.assertNotEquals(null, saved.AXF_CON_DT_LastSyncDatetime__c);
    }
  }

  @IsTest
  static void firstPhaseChainsTheNextOneKeepingTheFailures() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_PluggyConnection__c bad = connection('item-bad', 'Active');
      Test.startTest();
      phase(1, new Set<Id>{ bad.Id }, new Map<Id, String>{ bad.Id => 'x' })
        .finish(null);
      // Before stopTest runs it: only the chained phase 2 is queued.
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM AsyncApexJob
          WHERE ApexClass.Name = 'ALT_CLS_PluggySyncBatch'
        ]
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void aFirstPhaseFailureKeepsTheConnectionOutOfTheChainedPhase() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_PluggyConnection__c good = connection('item-g', 'Active');
      AXF_OBJ_PluggyConnection__c failed = connection('item-f', 'Active');
      bankAccount(good, 'acc-good');
      bankAccount(failed, 'acc-failed');
      RecordingMock mock = new RecordingMock();
      Test.setMock(HttpCalloutMock.class, mock);
      Test.startTest();
      // The real hand-over: phase 1 ends with an error and queues phase 2.
      phase(
          1,
          new Set<Id>{ good.Id, failed.Id },
          new Map<Id, String>{ failed.Id => 'HTTP 500' }
        )
        .finish(null);
      Test.stopTest();
      String calls = String.join(mock.urls, ' ');
      System.assert(calls.contains('accountId=acc-good'), calls);
      System.assert(!calls.contains('acc-failed'), calls);
    }
  }

  @IsTest
  static void scheduledExecuteStartsTheFullSync() {
    Test.startTest();
    new ALT_CLS_PluggySyncSchedule().execute(null);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'ALT_CLS_PluggySyncBatch'
      ]
    );
    Test.stopTest();
  }

  @IsTest
  static void scheduleRegistersTheDailyJobAndRunsTheBatch() {
    // A test name keeps the org's real daily job untouched.
    String jobName = 'Axon test - Sync diário Pluggy';
    Test.startTest();
    ALT_CLS_PluggySyncSchedule.scheduleDaily(jobName);
    // Running it again replaces the job instead of failing on the duplicate name.
    Id jobId = ALT_CLS_PluggySyncSchedule.scheduleDaily(jobName);
    Test.stopTest();
    System.assertEquals(
      1,
      [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :jobName]
    );
    CronTrigger cron = [
      SELECT CronExpression, CronJobDetail.Name
      FROM CronTrigger
      WHERE Id = :jobId
    ];
    System.assertEquals('0 0 3 * * ?', cron.CronExpression);
    System.assertEquals(jobName, cron.CronJobDetail.Name);
    System.assertEquals(
      'Axon - Sync diário Pluggy',
      ALT_CLS_PluggySyncSchedule.JOB_NAME
    );
  }
}
