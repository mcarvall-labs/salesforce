/**
 * @description Daily trigger of the full Pluggy sync. Register once per org with
 * ALT_CLS_PluggySyncSchedule.scheduleDaily() (03:00); the running user needs the
 * AXF_CP_PluggySync custom permission (AXF_PS_Configuracao).
 */
public with sharing class ALT_CLS_PluggySyncSchedule implements Schedulable {
  public static final String JOB_NAME = 'Axon - Sync diário Pluggy';
  public static final String DAILY_AT_3AM = '0 0 3 * * ?';

  public static Id scheduleDaily() {
    return System.schedule(
      JOB_NAME,
      DAILY_AT_3AM,
      new ALT_CLS_PluggySyncSchedule()
    );
  }

  public void execute(SchedulableContext context) {
    ALT_CLS_PluggySyncBatch.run(null);
  }
}
