/**
 * @description Generic one-time Schedulable wrapper used to re-enqueue a Queueable job after a delay.
 * Used to implement retry/backoff for Pluggy API rate limiting (HTTP 429), since Queueable jobs
 * cannot be delayed on their own and must be re-scheduled through a Schedulable instead.
 */
public with sharing class AXF_CLS_PluggyRetryScheduler implements Schedulable {

    private Queueable jobToRun;

    public AXF_CLS_PluggyRetryScheduler(Queueable jobToRun) {
        this.jobToRun = jobToRun;
    }

    public void execute(SchedulableContext ctx) {
        if (!Test.isRunningTest()) {
            System.enqueueJob(jobToRun);
        }
        System.abortJob(ctx.getTriggerId());
    }

    /**
     * @description Builds a Salesforce cron expression (seconds precision) for a one-time fire at the given moment.
     */
    public static String toCronExpression(Datetime fireTime) {
        return fireTime.second() + ' ' + fireTime.minute() + ' ' + fireTime.hour() + ' '
            + fireTime.day() + ' ' + fireTime.month() + ' ? ' + fireTime.year();
    }
}
