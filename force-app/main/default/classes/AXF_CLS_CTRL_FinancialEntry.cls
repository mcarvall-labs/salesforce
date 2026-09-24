/**
 * @description Thin LWC controller for the guided entry wizard (AXF-19). Delegates every
 * decision to AXF_CLS_FinancialEntryService; sanitizes unexpected exceptions.
 * AXF-153: the wizard's realization, Pluggy suggestions, manual search and one-click confirmation
 * delegate to ALT_CLS_ManualEntryService; JSON requests are parsed strictly and failures leave as a
 * sanitized {code}.
 */
public with sharing class AXF_CLS_CTRL_FinancialEntry {
  public class Capabilities {
    /** Link capability (AXF_CanLinkSource + AXF_CanRealize): Pluggy suggestions and confirmation. */
    @AuraEnabled
    public Boolean canReconcile = false;
    /** AXF_CanRealize: posting an entry that already happened. */
    @AuraEnabled
    public Boolean canRealize = false;
    @AuraEnabled
    public String matchingPolicy = ALT_CLS_ManualEntryService.MATCHING_POLICY;
  }

  @AuraEnabled(cacheable=true)
  public static Capabilities getCapabilities() {
    try {
      Capabilities result = new Capabilities();
      result.canReconcile = ALT_CLS_ManualEntryService.canReconcile();
      result.canRealize = ALT_CLS_ManualEntryService.canRealize();
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<AXF_CLS_FinancialEntryService.FundingSourceOption> getFundingSources(
    Id accountId
  ) {
    try {
      return AXF_CLS_FinancialEntryService.getFundingSources(accountId);
    } catch (Exception unexpected) {
      throw new AuraHandledException(
        'Não foi possível carregar as origens disponíveis.'
      );
    }
  }

  // Primitive params (not the service's inner DTO) so the LWC call binds reliably:
  // Aura does not populate the fields of an @AuraEnabled Apex class that is an inner
  // class of another top-level class (same limitation fixed in
  // AXF_CLS_CTRL_OnboardingProgress). AXF-19 / AXF-106.
  @AuraEnabled
  public static AXF_CLS_FinancialEntryService.EntryResult createEntry(
    Id accountId,
    String direction,
    Decimal magnitude,
    String currencyIsoCode,
    Date purchaseDate,
    Date dueDate,
    Id bankAccountId,
    Id creditCardId,
    String clientRequestId,
    Boolean trackConfirmation
  ) {
    try {
      if (accountId != null && bankAccountId == null && creditCardId == null) {
        // AXF-153: the wizard always posts on a current account, a card or a wallet.
        AXF_CLS_FinancialEntryService.EntryResult missing = new AXF_CLS_FinancialEntryService.EntryResult();
        missing.outcome = 'INVALID';
        missing.message = System.Label.AXF_ManualEntry_originRequired;
        return missing;
      }
      AXF_CLS_FinancialEntryService.EntryInput input = new AXF_CLS_FinancialEntryService.EntryInput();
      input.accountId = accountId;
      input.direction = direction;
      input.magnitude = magnitude;
      input.currencyIsoCode = currencyIsoCode;
      input.purchaseDate = purchaseDate;
      input.dueDate = dueDate;
      input.bankAccountId = bankAccountId;
      input.creditCardId = creditCardId;
      input.clientRequestId = clientRequestId;
      input.trackConfirmation = trackConfirmation;
      return AXF_CLS_FinancialEntryService.createEntry(input);
    } catch (Exception unexpected) {
      throw new AuraHandledException(
        'Não foi possível concluir. Tente novamente.'
      );
    }
  }

  /** @description AXF-153: posts an entry that already happened (manual fact or chosen Pluggy fact). */
  @AuraEnabled
  public static ALT_CLS_ManualEntryService.RealizeResult realizeEntry(
    String request
  ) {
    try {
      return new ALT_CLS_ManualEntryService()
        .realize(
          (ALT_CLS_ManualEntryService.RealizeInput) parse(
            request,
            ALT_CLS_ManualEntryService.RealizeInput.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  /** @description AXF-153: Pluggy facts inside the AXF-MATCHING@1.1.0 window of a draft or saved entry. */
  @AuraEnabled
  public static ALT_CLS_ManualEntryService.FactPage listFactSuggestions(
    String request
  ) {
    try {
      return new ALT_CLS_ManualEntryService()
        .suggest(
          (ALT_CLS_ManualEntryService.Draft) parse(
            request,
            ALT_CLS_ManualEntryService.Draft.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  /** @description AXF-153: manual search of Pluggy facts of the entry's source by period and description. */
  @AuraEnabled
  public static ALT_CLS_ManualEntryService.FactPage searchFacts(
    String request
  ) {
    try {
      return new ALT_CLS_ManualEntryService()
        .search(
          (ALT_CLS_ManualEntryService.SearchQuery) parse(
            request,
            ALT_CLS_ManualEntryService.SearchQuery.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  /** @description AXF-153: one explicit click links a displayed Pluggy fact to the saved entry. */
  @AuraEnabled
  public static ALT_CLS_ManualEntryService.ConfirmResult confirmFact(
    String request
  ) {
    try {
      return new ALT_CLS_ManualEntryService()
        .confirm(
          (ALT_CLS_ManualEntryService.ConfirmInput) parse(
            request,
            ALT_CLS_ManualEntryService.ConfirmInput.class
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
    if (
      failure instanceof ALT_CLS_ManualEntryService.ManualEntryException ||
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
