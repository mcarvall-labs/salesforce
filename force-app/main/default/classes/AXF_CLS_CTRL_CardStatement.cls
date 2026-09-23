/**
 * @description Controller exclusivo do LWC aXF_LWC_cardStatement (AXF-152). Fino: valida o JSON
 * de entrada, delega ao ALT_CLS_CardStatementService e devolve erros sanitizados como {code};
 * nunca stack trace, PII ou existencia de registros fora do contexto autorizado.
 */
public with sharing class AXF_CLS_CTRL_CardStatement {
  public class Context {
    @AuraEnabled
    public Boolean canUse = false;
    @AuraEnabled
    public Boolean canConfigure = false;
    /** Link capability: suggestions and one-click confirmation; reading needs only the context. */
    @AuraEnabled
    public Boolean canReconcile = false;
    @AuraEnabled
    public String matchingPolicy = ALT_CLS_CardStatementService.MATCHING_POLICY;
    @AuraEnabled
    public String calendarPolicy = ALT_CLS_CardStatementService.CALENDAR_POLICY;
  }

  @AuraEnabled(cacheable=true)
  public static Context getContext() {
    try {
      Context result = new Context();
      result.canUse = true;
      result.canReconcile = new ALT_CLS_CardStatementService().canReconcile();
      result.canConfigure = ALT_CLS_CardStatementService.canConfigure();
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static List<ALT_CLS_CardStatementService.CardView> listCards() {
    try {
      return new ALT_CLS_CardStatementService().listCards();
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_CardStatementService.InvoiceView getInvoice(
    String request
  ) {
    try {
      return new ALT_CLS_CardStatementService()
        .invoice(
          (ALT_CLS_CardStatementService.InvoiceQuery) parse(
            request,
            ALT_CLS_CardStatementService.InvoiceQuery.class
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
      return new ALT_CLS_CardStatementService()
        .suggest(
          (ALT_CLS_CardStatementService.SuggestionQuery) parse(
            request,
            ALT_CLS_CardStatementService.SuggestionQuery.class
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
      return new ALT_CLS_CardStatementService()
        .confirm(
          (ALT_CLS_CardStatementService.ConfirmInput) parse(
            request,
            ALT_CLS_CardStatementService.ConfirmInput.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_CardStatementService.CardView defineClosing(
    String request
  ) {
    try {
      return new ALT_CLS_CardStatementService()
        .defineClosing(
          (ALT_CLS_CardStatementService.ClosingInput) parse(
            request,
            ALT_CLS_CardStatementService.ClosingInput.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static Object parse(String request, Type shape) {
    if (String.isBlank(request)) {
      throw new ALT_CLS_CardStatementService.CardStatementException(
        'INVALID_INPUT'
      );
    }
    try {
      return JSON.deserializeStrict(request, shape);
    } catch (Exception failure) {
      throw new ALT_CLS_CardStatementService.CardStatementException(
        'INVALID_INPUT'
      );
    }
  }

  @TestVisible
  private static AuraHandledException safe(Exception failure) {
    String code;
    if (
      failure instanceof ALT_CLS_CardStatementService.CardStatementException ||
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
