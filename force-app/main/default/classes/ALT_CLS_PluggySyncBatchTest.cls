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
    return new ALT_CLS_PluggySyncBatch(null, phase, attempted, errors);
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
      Database.QueryLocator all = new ALT_CLS_PluggySyncBatch(null).start(null);
      Database.QueryLocator one = new ALT_CLS_PluggySyncBatch(failed.Id)
        .start(null);
      System.assertEquals(2, Database.query(all.getQuery()).size());
      System.assert(one.getQuery().contains('AND Id = :connectionFilter'));
      System.assertNotEquals(null, active.Id);
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
  static void scheduleRegistersTheDailyJobAndRunsTheBatch() {
    Test.startTest();
    Id jobId = ALT_CLS_PluggySyncSchedule.scheduleDaily();
    Test.stopTest();
    CronTrigger cron = [
      SELECT CronExpression, CronJobDetail.Name
      FROM CronTrigger
      WHERE Id = :jobId
    ];
    System.assertEquals('0 0 3 * * ?', cron.CronExpression);
    System.assertEquals(
      ALT_CLS_PluggySyncSchedule.JOB_NAME,
      cron.CronJobDetail.Name
    );
    new ALT_CLS_PluggySyncSchedule().execute(null);
  }
}
