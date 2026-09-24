/**
 * @description Controller exclusivo do LWC aXF_LWC_reconciliationQueue (AXF-154). Fino: valida o
 * JSON de entrada, delega ao ALT_CLS_ReconciliationQueueService e devolve erros sanitizados como
 * {code}; nunca stack trace, PII ou existencia de registros fora do contexto autorizado.
 */
public with sharing class AXF_CLS_CTRL_ReconciliationQueue {
  public class Context {
    /** Link capability: suggestions and one-click confirmation; reading needs only the context. */
    @AuraEnabled
    public Boolean canReconcile = false;
    @AuraEnabled
    public String matchingPolicy = ALT_CLS_ReconciliationQueueService.MATCHING_POLICY;
  }

  @AuraEnabled(cacheable=true)
  public static Context getContext() {
    try {
      Context result = new Context();
      result.canReconcile = new ALT_CLS_ReconciliationQueueService()
        .canReconcile();
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ReconciliationQueueService.SourceList listSources() {
    try {
      return new ALT_CLS_ReconciliationQueueService().listSources();
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ReconciliationQueueService.QueueView getQueue(
    String request
  ) {
    try {
      return new ALT_CLS_ReconciliationQueueService()
        .queue(
          (ALT_CLS_ReconciliationQueueService.QueueQuery) parse(
            request,
            ALT_CLS_ReconciliationQueueService.QueueQuery.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_BankStatementService.SuggestionPage listSuggestions(
    String request
  ) {
    try {
      return new ALT_CLS_ReconciliationQueueService()
        .suggest(
          (ALT_CLS_ReconciliationQueueService.SuggestionQuery) parse(
            request,
            ALT_CLS_ReconciliationQueueService.SuggestionQuery.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_BankStatementService.ConfirmResult confirmSuggestion(
    String request
  ) {
    try {
      return new ALT_CLS_ReconciliationQueueService()
        .confirm(
          (ALT_CLS_ReconciliationQueueService.ConfirmInput) parse(
            request,
            ALT_CLS_ReconciliationQueueService.ConfirmInput.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static Object parse(String request, Type shape) {
    if (String.isBlank(request)) {
      throw new ALT_CLS_ReconciliationQueueService.ReconciliationQueueException(
        'INVALID_INPUT'
      );
    }
    try {
      return JSON.deserializeStrict(request, shape);
    } catch (Exception failure) {
      throw new ALT_CLS_ReconciliationQueueService.ReconciliationQueueException(
        'INVALID_INPUT'
      );
    }
  }

  @TestVisible
  private static AuraHandledException safe(Exception failure) {
    String code;
    if (
      failure instanceof ALT_CLS_ReconciliationQueueService.ReconciliationQueueException ||
      failure instanceof ALT_CLS_SourceLinkService.SourceLinkException
    ) {
      code = failure.getMessage();
    } else if (
      failure instanceof QueryException ||
      failure instanceof System.SecurityException ||
      failure instanceof System.NoAccessException
    ) {
      code = 'NOT_ACCESSIBLE';
    } else if (failure instanceof DmlException) {
      code = 'REJECTED';
    } else {
      code = 'UNEXPECTED';
    }
    AuraHandledException result = new AuraHandledException(code);
    result.setMessage(code);
    return result;
  }
}
