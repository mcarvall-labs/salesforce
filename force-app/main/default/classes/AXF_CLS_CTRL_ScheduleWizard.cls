/** AXF-20 — thin controller for the schedule wizard LWC. */
public with sharing class AXF_CLS_CTRL_ScheduleWizard {
  // Primitive params (not the service's inner DTO) so the LWC call binds reliably:
  // Aura does not populate the fields of an @AuraEnabled Apex class that is an inner
  // class of another top-level class (same limitation fixed in
  // AXF_CLS_CTRL_OnboardingProgress). AXF-20 / AXF-106.
  @AuraEnabled
  public static ALT_CLS_AmortizationSchedule.ScheduleResult planSchedule(
    String modality,
    Decimal principal,
    Integer installments,
    Decimal periodRate,
    Date firstDueDate,
    Decimal fixedValue,
    Decimal flatFeePerInstallment,
    Decimal upfrontFee
  ) {
    AXF_CLS_ScheduleService.PlanInput input = new AXF_CLS_ScheduleService.PlanInput();
    input.modality = modality;
    input.principal = principal;
    input.installments = installments;
    input.periodRate = periodRate;
    input.firstDueDate = firstDueDate;
    input.fixedValue = fixedValue;
    input.flatFeePerInstallment = flatFeePerInstallment;
    input.upfrontFee = upfrontFee;
    return AXF_CLS_ScheduleService.plan(input);
  }

  // The nested PlanInput travels as JSON (planJson): Aura cannot bind a nested
  // inner-class DTO either.
  @AuraEnabled
  public static AXF_CLS_ScheduleService.SaveResult saveSchedule(
    String planJson,
    Id accountId,
    String direction,
    String currencyIsoCode,
    String groupKey
  ) {
    AXF_CLS_ScheduleService.SaveInput input = new AXF_CLS_ScheduleService.SaveInput();
    if (String.isNotBlank(planJson)) {
      input.plan = (AXF_CLS_ScheduleService.PlanInput) JSON.deserialize(
        planJson,
        AXF_CLS_ScheduleService.PlanInput.class
      );
    }
    input.accountId = accountId;
    input.direction = direction;
    input.currencyIsoCode = currencyIsoCode;
    input.groupKey = groupKey;
    return AXF_CLS_ScheduleService.save(input);
  }

  @AuraEnabled(cacheable=true)
  public static List<AXF_CLS_AuthorizedContextService.ContextView> authorizedContexts() {
    return AXF_CLS_AuthorizedContextService.listAuthorizedContexts();
  }
}
