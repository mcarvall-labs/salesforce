/**
 * @description Dedicated controller for aXF_LWC_reportCurrencyPreference (PROJECT_RULES §3).
 * Thin: validates input, delegates to AXF_CLS_ReportCurrencyService, returns typed DTOs,
 * never returns a stack trace. AXF-87.
 */
public with sharing class AXF_CLS_CTRL_ReportCurrencyPref {
  public class StateDTO {
    @AuraEnabled
    public List<AXF_CLS_ReportCurrencyService.CurrencyOption> options;
    @AuraEnabled
    public String currentIsoCode;
    @AuraEnabled
    public Boolean hasPersonalPreference;
    @AuraEnabled
    public String suggestedIsoCode;
  }

  public class SaveResultDTO {
    @AuraEnabled
    public Boolean applied;
    @AuraEnabled
    public Boolean confirmRequired;
    @AuraEnabled
    public String currentIsoCode;
    @AuraEnabled
    public String message;
  }

  @AuraEnabled(cacheable=true)
  public static StateDTO getState() {
    AXF_CLS_ReportCurrencyService svc = new AXF_CLS_ReportCurrencyService();
    StateDTO d = new StateDTO();
    d.options = svc.activeCurrencies();
    d.currentIsoCode = svc.effectivePreference();
    d.hasPersonalPreference = svc.hasPersonalPreference();
    d.suggestedIsoCode = svc.suggestedDefault();
    return d;
  }

  @AuraEnabled
  public static SaveResultDTO setPreference(
    String isoCode,
    Boolean overwriteExisting
  ) {
    AXF_CLS_ReportCurrencyService svc = new AXF_CLS_ReportCurrencyService();
    SaveResultDTO out = new SaveResultDTO();
    try {
      svc.setForCurrentUser(isoCode, overwriteExisting);
      out.applied = true;
      out.message = 'Preferencia de moeda salva.';
    } catch (AXF_CLS_ReportCurrencyException e) {
      if (e.getMessage().startsWith('CONFIRM_REQUIRED')) {
        out.applied = false;
        out.confirmRequired = true;
        out.message = e.getMessage().replace('CONFIRM_REQUIRED: ', '');
      } else {
        out.applied = false;
        out.message = e.getMessage();
      }
    }
    out.currentIsoCode = svc.effectivePreference();
    return out;
  }
}
