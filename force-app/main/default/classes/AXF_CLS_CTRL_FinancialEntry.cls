/**
 * @description Thin LWC controller for the guided entry wizard (AXF-19). Delegates every
 * decision to AXF_CLS_FinancialEntryService; sanitizes unexpected exceptions.
 */
public with sharing class AXF_CLS_CTRL_FinancialEntry {
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
}
