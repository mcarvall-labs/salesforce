/**
 * @description Daily entry point for the Pluggy transaction sync (AXF-12 AC1). Claims every
 * eligible scope of every active, consented connection and hands them to a single Queueable
 * chain — the same processing the on-demand "Sincronizar agora" uses. Schedule string comes
 * from AXF_PluggySyncPolicy__mdt (hour + time zone); registering the CronTrigger is an
 * install/ops step, not done here.
 *
 * Example (run as a user holding AXF_CanConfigure + AXF_PS_PluggyIntegration):
 *   System.schedule('AXF Pluggy Sync', '0 0 3 * * ?', new AXF_CLS_PluggySyncScheduler());
 */
public with sharing class AXF_CLS_PluggySyncScheduler implements Schedulable {
  public void execute(SchedulableContext ctx) {
    run();
  }

  /**
   * @description Claims scopes across all eligible connections and enqueues one worker
   * chain. Returns the enqueued job id, or null when there was nothing to do. A connection
   * that cannot be claimed (paused, consent gone, policy missing) is skipped, not fatal.
   */
  public static Id run() {
    AXF_CLS_PluggySyncService svc = new AXF_CLS_PluggySyncService();
    List<AXF_CLS_PluggySyncService.ClaimedScope> all = new List<AXF_CLS_PluggySyncService.ClaimedScope>();
    for (AXF_OBJ_PluggyConnection__c c : [
      SELECT Id
      FROM AXF_OBJ_PluggyConnection__c
      WHERE
        AXF_CON_PKL_CollectionState__c = 'ACTIVE'
        AND AXF_CON_PKL_ConsentState__c = 'ACTIVE'
      WITH USER_MODE
    ]) {
      try {
        all.addAll(svc.claimScopes(c.Id));
      } catch (Exception e) {
        // skip this connection; the health panel already reflects why
        continue;
      }
    }
    if (all.isEmpty()) {
      return null;
    }
    return System.enqueueJob(new AXF_CLS_PluggySyncQueueable(all));
  }
}
