/**
 * @description Monthly trigger of the recurring-contract extension. Register once per org with
 * ALT_CLS_ContractGenerationSchedule.scheduleMonthly() (day 1, 04:00).
 */
public with sharing class ALT_CLS_ContractGenerationSchedule implements Schedulable {
  public static final String JOB_NAME = 'Axon - Geração mensal de lançamentos dos contratos';
  public static final String MONTHLY_AT_4AM = '0 0 4 1 * ?';

  // Safe to run again: an existing job with the same name is replaced, not duplicated.
  public static Id scheduleMonthly() {
    return scheduleMonthly(JOB_NAME);
  }

  public static Id scheduleMonthly(String jobName) {
    for (CronTrigger existing : [
      SELECT Id
      FROM CronTrigger
      WHERE CronJobDetail.Name = :jobName
    ]) {
      System.abortJob(existing.Id);
    }
    return System.schedule(
      jobName,
      MONTHLY_AT_4AM,
      new ALT_CLS_ContractGenerationSchedule()
    );
  }

  public void execute(SchedulableContext context) {
    ALT_CLS_ContractGenerationBatch.run();
  }
}
