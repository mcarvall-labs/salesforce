/**
 * @description Daily trigger of the exchange-rate update on business days. Register once per org
 * with ALT_CLS_FxRateSchedule.scheduleDaily() (Monday to Friday, 14:00 org time, after the PTAX
 * closing bulletin).
 */
public with sharing class ALT_CLS_FxRateSchedule implements Schedulable {
  public static final String JOB_NAME = 'Axon - Atualização diária do câmbio (PTAX)';
  public static final String WEEKDAYS_AT_2PM = '0 0 14 ? * MON-FRI';

  // Safe to run again: an existing job with the same name is replaced, not duplicated.
  public static Id scheduleDaily() {
    return scheduleDaily(JOB_NAME);
  }

  public static Id scheduleDaily(String jobName) {
    for (CronTrigger existing : [
      SELECT Id
      FROM CronTrigger
      WHERE CronJobDetail.Name = :jobName
    ]) {
      System.abortJob(existing.Id);
    }
    return System.schedule(
      jobName,
      WEEKDAYS_AT_2PM,
      new ALT_CLS_FxRateSchedule()
    );
  }

  public void execute(SchedulableContext context) {
    System.enqueueJob(new ALT_CLS_FxRateJob());
  }
}
