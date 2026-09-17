/**
 * @description Controller exclusivo do LWC aXF_LWC_reconciliationWorkbench (AXF-30). Leitura
 * cacheable e mutacao sem cache; erros sanitizados como {code, reasons[]}; nunca stack trace, PII
 * ou existencia de registros nao autorizados. A superficie nao soma, nao converte e nao conclui:
 * cada figura exibida vem do servico.
 */
public with sharing class AXF_CLS_CTRL_ReconciliationWorkbench {
  public class Context {
    @AuraEnabled
    public Boolean canConfirm;
    @AuraEnabled
    public String policyVersion;
    @AuraEnabled
    public List<AXF_CLS_AuthorizedContextService.ContextView> holders;
  }

  @AuraEnabled(cacheable=true)
  public static Context getContext() {
    try {
      Context result = new Context();
      result.canConfirm =
        FeatureManagement.checkPermission(
          ALT_CLS_ReconciliationService.CP_CONFIRM
        ) && FeatureManagement.checkPermission('AXF_CanRealize');
      result.policyVersion = ALT_CLS_ReconciliationService.POLICY_VERSION;
      result.holders = result.canConfirm
        ? AXF_CLS_AuthorizedContextService.listAuthorizedContexts()
        : new List<AXF_CLS_AuthorizedContextService.ContextView>();
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled(cacheable=true)
  public static ALT_CLS_ReconciliationService.WorkbenchView preview(
    String request
  ) {
    try {
      if (String.isBlank(request)) {
        throw invalid();
      }
      return new ALT_CLS_ReconciliationService()
        .preview(
          (ALT_CLS_ReconciliationService.PreviewInput) parse(
            request,
            ALT_CLS_ReconciliationService.PreviewInput.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ReconciliationService.ConfirmResult confirm(
    String request
  ) {
    try {
      if (String.isBlank(request)) {
        throw invalid();
      }
      return new ALT_CLS_ReconciliationService()
        .confirm(
          (ALT_CLS_ReconciliationService.ConfirmInput) parse(
            request,
            ALT_CLS_ReconciliationService.ConfirmInput.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  /** GF-75: reenvio depois de timeout. Nunca repete o command: park e consulta sao explicitos. */
  @AuraEnabled
  public static ALT_CLS_ReconciliationService.WorkbenchView parkResultUnknown(
    String request
  ) {
    try {
      if (String.isBlank(request)) {
        throw invalid();
      }
      return new ALT_CLS_ReconciliationService()
        .parkResultUnknown(
          (ALT_CLS_ReconciliationService.AttemptInput) parse(
            request,
            ALT_CLS_ReconciliationService.AttemptInput.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ReconciliationService.WorkbenchView resolveResult(
    String request
  ) {
    try {
      if (String.isBlank(request)) {
        throw invalid();
      }
      return new ALT_CLS_ReconciliationService()
        .resolveResult(
          (ALT_CLS_ReconciliationService.AttemptInput) parse(
            request,
            ALT_CLS_ReconciliationService.AttemptInput.class
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
      throw new ALT_CLS_ReconciliationService.ReconciliationException(
        'INVALID_INPUT'
      );
    }
  }

  private static AuraHandledException invalid() {
    return sanitized('INVALID_INPUT', new List<String>());
  }

  private static AuraHandledException sanitized(
    String code,
    List<String> reasons
  ) {
    AuraHandledException result = new AuraHandledException(code);
    result.setMessage(
      JSON.serialize(
        new Map<String, Object>{ 'code' => code, 'reasons' => reasons }
      )
    );
    return result;
  }

  private static AuraHandledException safe(Exception failure) {
    if (failure instanceof AuraHandledException) {
      return (AuraHandledException) failure;
    }
    if (
      failure instanceof ALT_CLS_ReconciliationService.ReconciliationException
    ) {
      ALT_CLS_ReconciliationService.ReconciliationException typed = (ALT_CLS_ReconciliationService.ReconciliationException) failure;
      return sanitized(typed.code, typed.reasons);
    }
    if (
      failure instanceof ALT_CLS_RealizationService.RealizationException
    ) {
      return sanitized(failure.getMessage(), new List<String>());
    }
    if (
      failure instanceof JSONException ||
      failure instanceof System.StringException ||
      failure instanceof System.TypeException
    ) {
      return invalid();
    }
    if (
      failure instanceof System.QueryException &&
      failure.getMessage() != null &&
      failure.getMessage().contains('UNABLE_TO_LOCK_ROW')
    ) {
      // Lock contention is transient: tell the client a retry may succeed.
      return sanitized('LOCKED', new List<String>());
    }
    if (
      failure instanceof System.QueryException ||
      failure instanceof System.SecurityException ||
      failure instanceof System.NoAccessException
    ) {
      return sanitized('NOT_ACCESSIBLE', new List<String>());
    }
    if (failure instanceof DmlException) {
      DmlException dml = (DmlException) failure;
      if (dml.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
        return sanitized('CONFLICT', new List<String>());
      }
      return sanitized('REJECTED', new List<String>());
    }
    System.debug(
      LoggingLevel.ERROR,
      'AXF-30 UNEXPECTED: ' +
        failure.getTypeName() +
        ' ' +
        failure.getMessage()
    );
    return sanitized('UNEXPECTED', new List<String>());
  }
}
