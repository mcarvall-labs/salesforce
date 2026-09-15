/**
 * @description Controller exclusivo do LWC aXF_LWC_reconciliationReversal (AXF-141). Erros
 * sanitizados como {code}; nunca stack trace, PII ou existencia de registros nao autorizados.
 */
public with sharing class AXF_CLS_CTRL_ReconciliationReversal {
  public class Context {
    @AuraEnabled
    public Boolean canReverse;
    @AuraEnabled
    public String policyVersion;
    @AuraEnabled
    public List<String> reasons;
    @AuraEnabled
    public Integer pageSize;
    @AuraEnabled
    public List<ALT_CLS_AxonHolder.HolderView> holders;
  }

  @AuraEnabled(cacheable=true)
  public static Context getContext(String search) {
    try {
      Context result = new Context();
      result.canReverse =
        FeatureManagement.checkPermission(
          ALT_CLS_ReconciliationReversalService.CP_REVERSE
        ) && FeatureManagement.checkPermission('AXF_CanRealize');
      result.policyVersion = ALT_CLS_ReconciliationReversalService.POLICY_VERSION;
      result.reasons = ALT_CLS_ReconciliationReversalService.REASONS;
      result.pageSize = ALT_CLS_ReconciliationReversalService.DEFAULT_PAGE;
      result.holders = result.canReverse
        ? new ALT_CLS_AxonHolder().listHolders(search)
        : new List<ALT_CLS_AxonHolder.HolderView>();
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ReconciliationReversalService.AllocationPage listAllocations(
    String request
  ) {
    try {
      return new ALT_CLS_ReconciliationReversalService()
        .listAllocations(
          (ALT_CLS_ReconciliationReversalService.ListQuery) parse(
            request,
            ALT_CLS_ReconciliationReversalService.ListQuery.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ReconciliationReversalService.Result reverse(
    String request
  ) {
    try {
      return new ALT_CLS_ReconciliationReversalService()
        .reverse(
          (ALT_CLS_ReconciliationReversalService.Input) parse(
            request,
            ALT_CLS_ReconciliationReversalService.Input.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ReconciliationReversalService.Result priorReversal(
    Id allocationId
  ) {
    try {
      return new ALT_CLS_ReconciliationReversalService()
        .priorReversal(allocationId);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static Object parse(String request, Type shape) {
    try {
      return JSON.deserializeStrict(request, shape);
    } catch (Exception failure) {
      throw new ALT_CLS_ReconciliationReversalService.ReversalException(
        'INVALID_INPUT'
      );
    }
  }

  private static AuraHandledException safe(Exception failure) {
    String code;
    if (
      failure instanceof ALT_CLS_ReconciliationReversalService.ReversalException
    ) {
      code = failure.getMessage();
    } else if (
      failure instanceof QueryException ||
      failure instanceof System.SecurityException ||
      failure instanceof System.NoAccessException
    ) {
      code = 'NOT_ACCESSIBLE';
    } else {
      code = 'UNEXPECTED';
    }
    AuraHandledException result = new AuraHandledException(code);
    result.setMessage(code);
    return result;
  }
}
