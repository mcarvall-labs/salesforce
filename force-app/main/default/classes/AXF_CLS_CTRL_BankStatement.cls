/**
 * @description Controller exclusivo do LWC aXF_LWC_bankStatement (AXF-151). Fino: valida o JSON
 * de entrada, delega ao ALT_CLS_BankStatementService e devolve erros sanitizados como {code};
 * nunca stack trace, PII ou existencia de registros fora do contexto autorizado.
 */
public with sharing class AXF_CLS_CTRL_BankStatement {
  public class Context {
    @AuraEnabled
    public Boolean canUse = false;
    @AuraEnabled
    public Boolean canConfigure = false;
    /** Link capability: suggestions and one-click confirmation; reading needs only the context. */
    @AuraEnabled
    public Boolean canReconcile = false;
    @AuraEnabled
    public String matchingPolicy = ALT_CLS_BankStatementService.MATCHING_POLICY;
  }

  @AuraEnabled(cacheable=true)
  public static Context getContext() {
    try {
      Context result = new Context();
      result.canUse = true;
      result.canReconcile = new ALT_CLS_BankStatementService().canReconcile();
      result.canConfigure = ALT_CLS_BankStatementService.canConfigure();
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static List<ALT_CLS_BankStatementService.AccountView> listAccounts() {
    try {
      return new ALT_CLS_BankStatementService().listAccounts();
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_BankStatementService.StatementView getStatement(
    String request
  ) {
    try {
      return new ALT_CLS_BankStatementService()
        .statement(
          (ALT_CLS_BankStatementService.StatementQuery) parse(
            request,
            ALT_CLS_BankStatementService.StatementQuery.class
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
      return new ALT_CLS_BankStatementService()
        .suggest(
          (ALT_CLS_BankStatementService.SuggestionQuery) parse(
            request,
            ALT_CLS_BankStatementService.SuggestionQuery.class
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
      return new ALT_CLS_BankStatementService()
        .confirm(
          (ALT_CLS_BankStatementService.ConfirmInput) parse(
            request,
            ALT_CLS_BankStatementService.ConfirmInput.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_BankStatementService.AccountView updateBalance(
    String request
  ) {
    try {
      return new ALT_CLS_BankStatementService()
        .updateBalance(
          (ALT_CLS_BankStatementService.BalanceInput) parse(
            request,
            ALT_CLS_BankStatementService.BalanceInput.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_BankStatementService.RefreshResult refreshBalance(
    String request
  ) {
    try {
      RefreshRequest parsed = (RefreshRequest) parse(
        request,
        RefreshRequest.class
      );
      return new ALT_CLS_BankStatementService().refresh(parsed.bankAccountId);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  public class RefreshRequest {
    public Id bankAccountId;
  }

  private static Object parse(String request, Type shape) {
    if (String.isBlank(request)) {
      throw new ALT_CLS_BankStatementService.BankStatementException(
        'INVALID_INPUT'
      );
    }
    try {
      return JSON.deserializeStrict(request, shape);
    } catch (Exception failure) {
      throw new ALT_CLS_BankStatementService.BankStatementException(
        'INVALID_INPUT'
      );
    }
  }

  @TestVisible
  private static AuraHandledException safe(Exception failure) {
    String code;
    if (
      failure instanceof ALT_CLS_BankStatementService.BankStatementException ||
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
