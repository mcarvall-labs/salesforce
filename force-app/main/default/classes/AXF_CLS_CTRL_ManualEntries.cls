/**
 * @description Controller exclusivo do LWC aXF_LWC_manualEntries (AXF-153). Fino: valida o JSON de
 * entrada, delega ao ALT_CLS_ManualEntryService e devolve erros sanitizados como {code}; nunca stack
 * trace, PII ou existencia de registros fora do contexto autorizado.
 */
public with sharing class AXF_CLS_CTRL_ManualEntries {
  @AuraEnabled
  public static ALT_CLS_ManualEntryService.ReportView listEntries(
    String request
  ) {
    try {
      return new ALT_CLS_ManualEntryService()
        .listEntries(
          (ALT_CLS_ManualEntryService.ReportQuery) parse(
            request,
            ALT_CLS_ManualEntryService.ReportQuery.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static Object parse(String request, Type shape) {
    if (String.isBlank(request)) {
      throw new ALT_CLS_ManualEntryService.ManualEntryException(
        'INVALID_INPUT'
      );
    }
    try {
      return JSON.deserializeStrict(request, shape);
    } catch (Exception failure) {
      throw new ALT_CLS_ManualEntryService.ManualEntryException(
        'INVALID_INPUT'
      );
    }
  }

  @TestVisible
  private static AuraHandledException safe(Exception failure) {
    String code;
    if (failure instanceof ALT_CLS_ManualEntryService.ManualEntryException) {
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
