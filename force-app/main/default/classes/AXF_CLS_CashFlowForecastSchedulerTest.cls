@IsTest
private class AXF_CLS_CashFlowForecastSchedulerTest {
  @TestSetup
  static void setup() {
    AXF_CLS_CashFlowTestFactory.createDomainUser();
  }

  @IsTest
  static void scheduleMonthlyRegistersJob() {
    String jobId;
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Test.startTest();
      jobId = AXF_CLS_CashFlowForecastScheduler.scheduleMonthly();
      Test.stopTest();
    }
    CronTrigger ct = [
      SELECT CronExpression, CronJobDetail.Name
      FROM CronTrigger
      WHERE Id = :jobId
    ];
    Assert.areEqual('0 0 3 1 * ?', ct.CronExpression);
    Assert.areEqual('AXF Cash Flow Forecast - Monthly', ct.CronJobDetail.Name);
  }

  @IsTest
  static void executeExtendsActiveGroups() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Account holder = AXF_CLS_CashFlowTestFactory.createAccount(
        'Scheduler Holder'
      );
      AXF_OBJ_InstallmentGroup__c groupRecord = new AXF_OBJ_InstallmentGroup__c(
        AXF_IG_PKL_GroupType__c = 'RECURRING'
      );
      insert groupRecord;
      AXF_OBJ_CashFlow__c entry = AXF_CLS_CashFlowTestFactory.buildCashFlow(
        true,
        holder.Id,
        'Assinatura',
        50,
        Date.today().addMonths(1),
        'PENDENTE'
      );
      entry.AXF_CF_LKP_InstallmentGroup__c = groupRecord.Id;
      insert entry;

      Test.startTest();
      new AXF_CLS_CashFlowForecastScheduler().execute(null);
      Test.stopTest();

      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM AXF_OBJ_CashFlow__c
          WHERE AXF_CF_LKP_InstallmentGroup__c = :groupRecord.Id
        ]
      );
    }
  }
}
