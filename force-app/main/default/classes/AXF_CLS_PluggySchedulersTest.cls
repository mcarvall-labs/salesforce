/**
 * @description Tests for AXF_CLS_PluggyItemSyncScheduler and AXF_CLS_PluggyRetryScheduler.
 */
@IsTest
private class AXF_CLS_PluggySchedulersTest {
  @TestSetup
  static void setup() {
    AXF_CLS_PluggyTestFactory.createTestUser();
  }

  @IsTest
  static void scheduleDailyRegistersNightlyJob() {
    Test.setMock(
      HttpCalloutMock.class,
      AXF_CLS_PluggyTestFactory.itemSyncMock()
    );
    String jobId;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      jobId = AXF_CLS_PluggyItemSyncScheduler.scheduleDaily();
      Test.stopTest();
    }
    CronTrigger ct = [
      SELECT CronExpression, CronJobDetail.Name
      FROM CronTrigger
      WHERE Id = :jobId
    ];
    Assert.areEqual('0 0 3 * * ?', ct.CronExpression);
    Assert.areEqual('AXF Pluggy Item Sync - Daily', ct.CronJobDetail.Name);
  }

  @IsTest
  static void executeEnqueuesItemSyncQueueable() {
    Test.setMock(
      HttpCalloutMock.class,
      AXF_CLS_PluggyTestFactory.itemSyncMock()
    );
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      new AXF_CLS_PluggyItemSyncScheduler().execute(null);
      Assert.areEqual(
        1,
        Limits.getQueueableJobs(),
        'Scheduler must enqueue the item sync queueable'
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void toCronExpressionBuildsOneTimeExpression() {
    Datetime fireTime = Datetime.newInstance(2026, 10, 1, 8, 30, 15);
    Assert.areEqual(
      '15 30 8 1 10 ? 2026',
      AXF_CLS_PluggyRetryScheduler.toCronExpression(fireTime)
    );
  }

  @IsTest
  static void retrySchedulerFiresOnceAndAbortsItself() {
    Queueable job = new AXF_CLS_PluggyBankAccountSyncQueueable(
      new List<AXF_OBJ_BankAccount__c>()
    );
    String jobId;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      jobId = System.schedule(
        'AXF_PluggyRetry_Test',
        AXF_CLS_PluggyRetryScheduler.toCronExpression(
          Datetime.now().addMinutes(5)
        ),
        new AXF_CLS_PluggyRetryScheduler(job)
      );
      Assert.areEqual(1, [SELECT COUNT() FROM CronTrigger WHERE Id = :jobId]);
      Test.stopTest();
    }
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM CronTrigger WHERE Id = :jobId],
      'One-time retry job aborts itself after running'
    );
  }
}
