/**
 * @description Controller exclusivo do LWC aXF_LWC_confidencePanel (AXF-143). Erros
 * sanitizados como {code}; nunca stack trace, PII ou existencia de registros nao autorizados.
 * O nivel e as acoes permitidas vem do servico; a UI apenas renderiza.
 */
public with sharing class AXF_CLS_CTRL_ConfidencePanel {
  @AuraEnabled(cacheable=true)
  public static List<ALT_CLS_ConfidencePanelService.HolderOption> getHolders() {
    try {
      return new ALT_CLS_ConfidencePanelService().listHolders();
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ConfidencePanelService.Panel explain(
    List<Id> accountIds
  ) {
    try {
      return new ALT_CLS_ConfidencePanelService().explain(accountIds);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static AuraHandledException safe(Exception failure) {
    String code = 'UNEXPECTED';
    if (failure instanceof ALT_CLS_ConfidencePanelService.ConfidenceException) {
      code = ((ALT_CLS_ConfidencePanelService.ConfidenceException) failure)
        .code;
    } else if (
      failure instanceof System.QueryException ||
      failure instanceof System.SecurityException ||
      failure instanceof System.NoAccessException
    ) {
      code = 'NOT_ACCESSIBLE';
    }
    AuraHandledException result = new AuraHandledException(code);
    result.setMessage(code);
    return result;
  }
}
