/**
 * @description Controller exclusivo do LWC aXF_LWC_forecastComparison (AXF-137). Erros
 * sanitizados como {code}; nunca stack trace, PII ou existencia de registros nao autorizados.
 * Horizontes, cenarios, totais e confianca vem do motor; a UI apenas renderiza e anuncia.
 */
public with sharing class AXF_CLS_CTRL_ForecastComparison {
  public class Context {
    @AuraEnabled
    public Boolean canCompare;
    @AuraEnabled
    public List<Integer> horizons;
    @AuraEnabled
    public String policyVersion;
    @AuraEnabled
    public List<ALT_CLS_AxonHolder.HolderView> holders;
  }

  @AuraEnabled(cacheable=true)
  public static Context getContext(String search) {
    try {
      Context result = new Context();
      result.canCompare = FeatureManagement.checkPermission(
        ALT_CLS_ForecastComparisonService.CP_COMPARE
      );
      result.horizons = ALT_CLS_ForecastComparisonService.HORIZONS;
      result.policyVersion = ALT_CLS_ForecastComparisonService.POLICY_VERSION;
      result.holders = result.canCompare
        ? new ALT_CLS_AxonHolder().listHolders(search)
        : new List<ALT_CLS_AxonHolder.HolderView>();
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ForecastComparisonService.Result compare(
    String request
  ) {
    try {
      ALT_CLS_ForecastComparisonService.Input input;
      try {
        input = (ALT_CLS_ForecastComparisonService.Input) JSON.deserializeStrict(
          request,
          ALT_CLS_ForecastComparisonService.Input.class
        );
      } catch (Exception malformed) {
        throw sanitized('INVALID_INPUT');
      }
      return new ALT_CLS_ForecastComparisonService().compare(input);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static AuraHandledException safe(Exception failure) {
    if (failure instanceof AuraHandledException) {
      return (AuraHandledException) failure;
    }
    String code = 'UNEXPECTED';
    if (
      failure instanceof ALT_CLS_ForecastComparisonService.ForecastException
    ) {
      code = ((ALT_CLS_ForecastComparisonService.ForecastException) failure)
        .code;
    } else if (
      failure instanceof System.QueryException ||
      failure instanceof System.SecurityException ||
      failure instanceof System.NoAccessException
    ) {
      code = 'NOT_ACCESSIBLE';
    }
    System.debug(LoggingLevel.ERROR, 'Forecast comparison failure: ' + failure);
    return sanitized(code);
  }

  private static AuraHandledException sanitized(String code) {
    AuraHandledException result = new AuraHandledException(code);
    result.setMessage(code);
    return result;
  }
}
