/**
 * @description Controller exclusivo do LWC aXF_LWC_compositeReversal (AXF-142). Expoe reversao
 * composta (ALT_CLS_CompositeReversalService) e redistribuicao (ALT_CLS_ReconciliationService)
 * ao mesmo molde de AXF_CLS_CTRL_ReconciliationReversal: erros sanitizados como {code}, nunca
 * stack trace, PII ou existencia de registros nao autorizados.
 */
public with sharing class AXF_CLS_CTRL_CompositeReversal {
  public class Context {
    @AuraEnabled
    public Boolean canReverse;
    @AuraEnabled
    public Boolean canRedistribute;
    @AuraEnabled
    public String policyVersion;
    @AuraEnabled
    public String redistributePolicyVersion;
    @AuraEnabled
    public List<String> reasons;
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
      result.canRedistribute =
        FeatureManagement.checkPermission(
          ALT_CLS_ReconciliationService.CP_CONFIRM
        ) && FeatureManagement.checkPermission('AXF_CanRealize');
      result.policyVersion = ALT_CLS_CompositeReversalService.POLICY_VERSION;
      result.redistributePolicyVersion = ALT_CLS_ReconciliationService.POLICY_VERSION;
      result.reasons = ALT_CLS_ReconciliationReversalService.REASONS;
      result.holders = (result.canReverse || result.canRedistribute)
        ? new ALT_CLS_AxonHolder().listHolders(search)
        : new List<ALT_CLS_AxonHolder.HolderView>();
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static List<ALT_CLS_CompositeReversalService.RcnSummary> listReconciliations(
    Id accountId
  ) {
    try {
      return new ALT_CLS_CompositeReversalService()
        .listReconciliations(accountId);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_CompositeReversalService.RcnView listAllocations(
    Id reconciliationId
  ) {
    try {
      return new ALT_CLS_CompositeReversalService()
        .listAllocations(reconciliationId);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_CompositeReversalService.Result reverseComposite(
    String request
  ) {
    try {
      return new ALT_CLS_CompositeReversalService()
        .reverse(
          (ALT_CLS_CompositeReversalService.Input) parse(
            request,
            ALT_CLS_CompositeReversalService.Input.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ReconciliationService.ConfirmResult redistribute(
    String request
  ) {
    try {
      return new ALT_CLS_ReconciliationService()
        .redistribute(
          (ALT_CLS_ReconciliationService.RedistributeInput) parse(
            request,
            ALT_CLS_ReconciliationService.RedistributeInput.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static Object parse(String request, Type shape) {
    try {
      return JSON.deserializeStrict(request, shape);
    } catch (Exception failure) {
      throw new ALT_CLS_CompositeReversalService.CompositeReversalException(
        'INVALID_INPUT'
      );
    }
  }

  private static AuraHandledException safe(Exception failure) {
    String code;
    if (
      failure instanceof ALT_CLS_CompositeReversalService.CompositeReversalException
    ) {
      code = failure.getMessage();
    } else if (
      failure instanceof ALT_CLS_ReconciliationReversalService.ReversalException
    ) {
      code = failure.getMessage();
    } else if (
      failure instanceof ALT_CLS_ReconciliationService.ReconciliationException
    ) {
      code = ((ALT_CLS_ReconciliationService.ReconciliationException) failure)
        .code;
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
