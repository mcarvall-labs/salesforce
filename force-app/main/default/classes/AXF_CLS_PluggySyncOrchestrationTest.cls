/**
 * @description AXF-12 — the Queueable processes a scope and the Scheduler claims every
 * eligible connection and hands work to one chain (daily == on-demand processing).
 */
@IsTest
private class AXF_CLS_PluggySyncOrchestrationTest {
  @TestSetup
  static void seed() {
    AXF_CLS_PluggyTestData.grantIntegrationAccess();
    AXF_CLS_PluggyTestData.config(false, 'A', 'TESTED_OK');
    AXF_OBJ_PluggyConnection__c conn = AXF_CLS_PluggyTestData.connection(
      'ITEMORCH'
    );
    AXF_CLS_PluggyTestData.bankAccount(conn.Id, 'ORCH-BANK-1', true);
  }

  static void policy() {
    AXF_CLS_PluggySyncService.canConfigureOverride = true;
    AXF_CLS_PluggySyncPolicy.overrideRecord = AXF_CLS_PluggyTestData.syncPolicy(
      100,
      10,
      3
    );
  }

  static AXF_CLS_PluggyHttpCalloutMock mockWithOnePage() {
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.txPages = new List<String>{
      AXF_CLS_PluggyTestData.txPage(
        new List<Map<String, Object>>{
          new Map<String, Object>{
            'id' => 'orch-1',
            'amount' => '-42.00',
            'type' => 'DEBIT'
          }
        },
        null
      )
    };
    return mock;
  }

  @IsTest
  static void queueableRunsAScope() {
    policy();
    Test.setMock(HttpCalloutMock.class, mockWithOnePage());
    Id connId = [SELECT Id FROM AXF_OBJ_PluggyConnection__c LIMIT 1].Id;
    List<AXF_CLS_PluggySyncService.ClaimedScope> scopes = new AXF_CLS_PluggySyncService()
      .claimScopes(connId);

    Test.startTest();
    System.enqueueJob(new AXF_CLS_PluggySyncQueueable(scopes));
    Test.stopTest();

    System.assertEquals(
      1,
      [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c]
    );
    System.assertEquals(
      'SUCCEEDED',
      [
        SELECT AXF_INR_PKL_State__c
        FROM AXF_OBJ_IntegrationRun__c
        WHERE AXF_INR_PKL_Product__c = 'TRANSACTIONS'
        LIMIT 1
      ]
      .AXF_INR_PKL_State__c
    );
  }

  @IsTest
  static void queueableExecuteProcessesAndCarriesRemainingWork() {
    AXF_CLS_PluggySyncService.canConfigureOverride = true;
    AXF_CLS_PluggySyncPolicy.overrideRecord = AXF_CLS_PluggyTestData.syncPolicy(
      100,
      1, // checkpoint after one page -> the scope asks to continue
      3
    );
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.txPages = new List<String>{
      AXF_CLS_PluggyTestData.txPage(
        new List<Map<String, Object>>{
          new Map<String, Object>{
            'id' => 'q0',
            'amount' => '-1.00',
            'type' => 'DEBIT'
          }
        },
        '1'
      ),
      AXF_CLS_PluggyTestData.txPage(
        new List<Map<String, Object>>{
          new Map<String, Object>{
            'id' => 'q1',
            'amount' => '-2.00',
            'type' => 'DEBIT'
          }
        },
        null
      )
    };
    Test.setMock(HttpCalloutMock.class, mock);
    Id connId = [SELECT Id FROM AXF_OBJ_PluggyConnection__c LIMIT 1].Id;
    List<AXF_CLS_PluggySyncService.ClaimedScope> scopes = new AXF_CLS_PluggySyncService()
      .claimScopes(connId);

    Test.startTest();
    new AXF_CLS_PluggySyncQueueable(scopes).execute(null);
    Test.stopTest();

    // one page in -> the run is still RUNNING with a saved cursor (chain would continue it)
    System.assertEquals(
      'RUNNING',
      [
        SELECT AXF_INR_PKL_State__c
        FROM AXF_OBJ_IntegrationRun__c
        WHERE AXF_INR_PKL_Product__c = 'TRANSACTIONS'
        LIMIT 1
      ]
      .AXF_INR_PKL_State__c
    );
  }

  @IsTest
  static void queueableWithNothingToDoIsHarmless() {
    policy();
    Test.setMock(HttpCalloutMock.class, mockWithOnePage());
    Test.startTest();
    System.enqueueJob(new AXF_CLS_PluggySyncQueueable(null));
    new AXF_CLS_PluggySyncQueueable(
        new List<AXF_CLS_PluggySyncService.ClaimedScope>()
      )
      .execute(null);
    Test.stopTest();
    System.assertEquals(
      0,
      [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c]
    );
  }

  @IsTest
  static void queueableSwallowsAnUnexpectedScopeFailure() {
    policy();
    Test.setMock(HttpCalloutMock.class, mockWithOnePage());
    List<AXF_CLS_PluggySyncService.ClaimedScope> bad = new List<AXF_CLS_PluggySyncService.ClaimedScope>{
      null
    };
    Test.startTest();
    new AXF_CLS_PluggySyncQueueable(bad).execute(null); // must not throw
    Test.stopTest();
    System.assertEquals(
      0,
      [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c]
    );
  }

  @IsTest
  static void schedulerClaimsAndEnqueues() {
    policy();
    Test.setMock(HttpCalloutMock.class, mockWithOnePage());

    Test.startTest();
    Id jobId = AXF_CLS_PluggySyncScheduler.run();
    Test.stopTest();

    System.assertNotEquals(null, jobId, 'a worker chain was enqueued');
    System.assertEquals(
      1,
      [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c]
    );
  }

  @IsTest
  static void schedulerSkipsAConnectionThatCannotBeClaimed() {
    AXF_CLS_PluggySyncService.canConfigureOverride = true;
    AXF_CLS_PluggySyncPolicy.forceMissing = true; // claimScopes throws -> skipped
    Test.setMock(HttpCalloutMock.class, mockWithOnePage());
    Test.startTest();
    Id jobId = AXF_CLS_PluggySyncScheduler.run();
    Test.stopTest();
    System.assertEquals(
      null,
      jobId,
      'nothing enqueued when every connection is skipped'
    );
  }

  @IsTest
  static void schedulerExecuteEntryPoint() {
    policy();
    Test.setMock(HttpCalloutMock.class, mockWithOnePage());
    Test.startTest();
    String cron = '0 0 3 1 1 ? 2099';
    System.schedule(
      'AXF Pluggy Sync test',
      cron,
      new AXF_CLS_PluggySyncScheduler()
    );
    Test.stopTest();
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE CronJobDetail.Name = 'AXF Pluggy Sync test'
      ]
    );
  }
}
