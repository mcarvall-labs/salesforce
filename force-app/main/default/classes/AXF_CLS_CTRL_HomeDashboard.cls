/**
 * @description Controller exclusivo do LWC aXF_LWC_homeDashboard (Inicio do app Axon Finance).
 * Erros sanitizados como {code}; nunca stack trace, PII ou existencia de registros nao
 * autorizados. Todo calculo vem de ALT_CLS_HomeDashboard.
 */
public with sharing class AXF_CLS_CTRL_HomeDashboard {
  @AuraEnabled
  public static ALT_CLS_HomeDashboard.DashboardView getDashboard(Id holderId) {
    try {
      if (
        holderId != null &&
        holderId.getSObjectType() != Account.SObjectType
      ) {
        throw new ALT_CLS_HomeDashboard.DashboardException('INVALID_INPUT');
      }
      return new ALT_CLS_HomeDashboard().dashboard(holderId);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static AuraHandledException safe(Exception failure) {
    String code = 'UNEXPECTED';
    if (failure instanceof ALT_CLS_HomeDashboard.DashboardException) {
      code = failure.getMessage();
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
