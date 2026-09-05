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

  @AuraEnabled
  public static AXF_CLS_FinancialEntryService.EntryResult createEntry(
    AXF_CLS_FinancialEntryService.EntryInput input
  ) {
    try {
      return AXF_CLS_FinancialEntryService.createEntry(input);
    } catch (Exception unexpected) {
      throw new AuraHandledException('Não foi possível concluir. Tente novamente.');
    }
  }
}
