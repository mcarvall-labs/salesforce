/** AXF-20 — thin controller for the schedule wizard LWC. */
public with sharing class AXF_CLS_CTRL_ScheduleWizard {
  @AuraEnabled
  public static ALT_CLS_AmortizationSchedule.ScheduleResult planSchedule(
    AXF_CLS_ScheduleService.PlanInput input
  ) {
    return AXF_CLS_ScheduleService.plan(input);
  }

  @AuraEnabled
  public static AXF_CLS_ScheduleService.SaveResult saveSchedule(
    AXF_CLS_ScheduleService.SaveInput input
  ) {
    return AXF_CLS_ScheduleService.save(input);
  }

  @AuraEnabled(cacheable=true)
  public static List<AXF_CLS_AuthorizedContextService.ContextView> authorizedContexts() {
    return AXF_CLS_AuthorizedContextService.listAuthorizedContexts();
  }
}
