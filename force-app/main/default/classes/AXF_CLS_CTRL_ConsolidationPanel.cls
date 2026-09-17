/**
 * @description Controller exclusivo do LWC aXF_LWC_consolidationPanel (AXF-125). Erros
 * sanitizados como {code}; nunca stack trace, PII ou existencia de registros nao autorizados.
 * Totais, confianca, exclusoes e o indicador comparavel vem de ALT_CLS_ConsolidationService
 * (AXF-122/123/128); a moeda de apresentacao vem da preferencia canonica (AXF-87). A UI apenas
 * renderiza e anuncia — nada e somado, convertido ou derivado aqui.
 */
public with sharing class AXF_CLS_CTRL_ConsolidationPanel {
  private static final String CP_CONSOLIDATE = 'AXF_CanConsolidate';

  public class Context {
    @AuraEnabled
    public Boolean canConsolidate;
    @AuraEnabled
    public List<ALT_CLS_AxonHolder.HolderView> holders;
    @AuraEnabled
    public List<AXF_CLS_ReportCurrencyService.CurrencyOption> currencies;
    @AuraEnabled
    public String defaultReportingIso;
  }

  @AuraEnabled(cacheable=true)
  public static Context getContext() {
    try {
      Context result = new Context();
      result.canConsolidate = FeatureManagement.checkPermission(CP_CONSOLIDATE);
      result.holders = result.canConsolidate
        ? new ALT_CLS_AxonHolder().listHolders(null)
        : new List<ALT_CLS_AxonHolder.HolderView>();
      result.currencies = new List<AXF_CLS_ReportCurrencyService.CurrencyOption>();
      try {
        // The presentation-currency catalogue is its own grant (AXF-87 read through
        // AXF_PS_ReportCurrency). A holder of the consolidation capability who does not have it still
        // gets the consolidated view — every total in its own currency, and the surface says in words
        // that no presentation currency was chosen — instead of losing the whole panel to it.
        AXF_CLS_ReportCurrencyService currencies = new AXF_CLS_ReportCurrencyService();
        result.currencies = currencies.activeCurrencies();
        result.defaultReportingIso = currencies.effectivePreference();
      } catch (System.QueryException notGranted) {
        System.debug(
          LoggingLevel.INFO,
          'Presentation currency not granted: ' + notGranted
        );
      }
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ConsolidationService.Result consolidate(
    List<Id> accountIds,
    String reportingIso
  ) {
    try {
      ALT_CLS_ConsolidationService.ScopeInput input = new ALT_CLS_ConsolidationService.ScopeInput();
      input.accountIds = accountIds;
      input.reportingIso = reportingIso;
      return new ALT_CLS_ConsolidationService().consolidate(input);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static AuraHandledException safe(Exception failure) {
    String code = 'UNEXPECTED';
    if (
      failure instanceof ALT_CLS_ConsolidationService.ConsolidationException
    ) {
      code = ((ALT_CLS_ConsolidationService.ConsolidationException) failure)
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
