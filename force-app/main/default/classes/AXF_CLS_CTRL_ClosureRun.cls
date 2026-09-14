/**
 * @description Controller exclusivo do LWC aXF_LWC_closureRun (AXF-119). Erros sanitizados
 * como {code}; nunca stack trace, PII ou existencia de registros nao autorizados.
 */
public with sharing class AXF_CLS_CTRL_ClosureRun {
  @AuraEnabled(cacheable=true)
  public static Boolean canClose() {
    return FeatureManagement.checkPermission(
      ALT_CLS_ClosureOrchestrator.CP_CLOSE
    );
  }

  @AuraEnabled(cacheable=true)
  public static List<AXF_CLS_AuthorizedContextService.ContextView> getHolders() {
    try {
      return AXF_CLS_AuthorizedContextService.listAuthorizedContexts();
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static List<ALT_CLS_ClosureOrchestrator.RunView> listRuns() {
    try {
      return new ALT_CLS_ClosureOrchestrator().listRuns();
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ClosureOrchestrator.RunView request(
    Id accountId,
    Boolean legalHold
  ) {
    try {
      return new ALT_CLS_ClosureOrchestrator().request(accountId, legalHold);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ClosureOrchestrator.RunView advance(
    Id runId,
    Decimal expectedVersion
  ) {
    try {
      return new ALT_CLS_ClosureOrchestrator().advance(runId, expectedVersion);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ClosureOrchestrator.RunView reconcile(
    Id runId,
    Decimal expectedVersion
  ) {
    try {
      return new ALT_CLS_ClosureOrchestrator()
        .reconcile(runId, expectedVersion);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ClosureOrchestrator.RunView attachExportEvidence(
    Id runId,
    String evidenceRef,
    Decimal expectedVersion
  ) {
    try {
      return new ALT_CLS_ClosureOrchestrator()
        .attachExportEvidence(runId, evidenceRef, expectedVersion);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ClosureOrchestrator.RunView read(Id runId) {
    try {
      return new ALT_CLS_ClosureOrchestrator().read(runId);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static AuraHandledException safe(Exception failure) {
    String code = 'UNEXPECTED';
    if (failure instanceof ALT_CLS_ClosureOrchestrator.ClosureException) {
      code = ((ALT_CLS_ClosureOrchestrator.ClosureException) failure).code;
    } else if (
      failure instanceof System.QueryException ||
      failure instanceof System.SecurityException ||
      failure instanceof System.NoAccessException
    ) {
      code = 'NOT_ACCESSIBLE';
    } else if (failure instanceof DmlException) {
      code = 'REJECTED';
    }
    AuraHandledException result = new AuraHandledException(code);
    result.setMessage(code);
    return result;
  }
}
