/**
 * @description       :
 * @author            : Michel Carvalho Lopes
 * @group             : Altice Labs
 * @last modified on  : 07-19-2026
 * @last modified by  : Michel Carvalho Lopes
 * @tested with       :
 * @version           : 1.0
 * @modification log  :
 * Modifications Log
 * Ver   Date         Author                  Modification
 * 1.0   07-19-2026   Michel Carvalho Lopes   Initial Version
**/
public with sharing class AXF_CLS_PluggyItemSyncScheduler implements Schedulable {

    private static final String DAILY_CRON_EXPRESSION = '0 0 3 * * ?';
    private static final String JOB_NAME = 'AXF Pluggy Item Sync - Daily';

    public void execute(SchedulableContext context) {
        System.enqueueJob(new AXF_CLS_PluggyItemSyncQueueable());
    }

    public static String scheduleDaily() {
        return System.schedule(JOB_NAME, DAILY_CRON_EXPRESSION, new AXF_CLS_PluggyItemSyncScheduler());
    }
}