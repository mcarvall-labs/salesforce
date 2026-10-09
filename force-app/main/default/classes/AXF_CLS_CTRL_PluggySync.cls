public with sharing class AXF_CLS_CTRL_PluggySync {
  public class SyncView {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Integer transactions;
  }

  // Manual refresh of one period of a bank account or credit card from Pluggy. The period
  // bounds are inclusive; the card also re-reads its invoices.
  @AuraEnabled
  public static SyncView syncPeriod(
    Id recordId,
    Date periodStart,
    Date periodEnd
  ) {
    if (recordId == null || periodStart == null || periodEnd == null) {
      throw new AuraHandledException('Informe o registro e o período.');
    }
    if (periodEnd < periodStart) {
      throw new AuraHandledException('Período inválido.');
    }
    SyncView view = new SyncView();
    SObjectType type = recordId.getSObjectType();
    if (type == AXF_OBJ_BankAccount__c.SObjectType) {
      ALT_CLS_PluggyTransactionSync.Result result = new ALT_CLS_PluggyTransactionSync()
        .sync(recordId, periodStart, periodEnd);
      view.success = result.success;
      view.message = result.message;
      view.transactions = result.transactions;
    } else if (type == AXF_OBJ_CreditCard__c.SObjectType) {
      ALT_CLS_PluggyCardSync.Result result = new ALT_CLS_PluggyCardSync()
        .sync(recordId, periodStart, periodEnd);
      view.success = result.success;
      view.message = result.message;
      view.transactions = result.transactions;
    } else {
      throw new AuraHandledException(
        'Sincronização disponível só para conta bancária e cartão de crédito.'
      );
    }
    return view;
  }
}
