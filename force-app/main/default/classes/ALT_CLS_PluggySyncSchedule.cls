/**
 * @description Daily trigger of the full Pluggy sync. Register once per org with
 * ALT_CLS_PluggySyncSchedule.scheduleDaily() (03:00); the running user needs the
 * AXF_CP_PluggySync custom permission (AXF_PS_Configuracao).
 */
public with sharing class ALT_CLS_PluggySyncSchedule implements Schedulable {
  public static final String JOB_NAME = 'Axon - Sync diário Pluggy';
  public static final String DAILY_AT_3AM = '0 0 3 * * ?';

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
      DAILY_AT_3AM,
      new ALT_CLS_PluggySyncSchedule()
    );
  }

  public void execute(SchedulableContext context) {
    ALT_CLS_PluggySyncBatch.run(null);
  }
}
