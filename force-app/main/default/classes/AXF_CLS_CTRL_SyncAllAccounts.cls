/**
 * @description Dedicated controller for the aXF_LWC_syncAllAccounts LWC (sync-all-accounts
 * button). Thin entry point that delegates to ALT_CLS_ManualSync for the actual sync
 * orchestration, per PROJECT_RULES.md §3.
 */
public with sharing class AXF_CLS_CTRL_SyncAllAccounts {
  public class SyncExecutionResult {
    @AuraEnabled
    public Boolean isSuccess;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Integer bankAccountsSynced;
    @AuraEnabled
    public Integer creditCardsSynced;
    @AuraEnabled
    public Integer connectionsProcessed;
    @AuraEnabled
    public Integer transactionsSynced;
    @AuraEnabled
    public Integer invoicesSynced;
    @AuraEnabled
    public List<String> errors;

    public SyncExecutionResult(
      ALT_CLS_ManualSync.SyncExecutionResult businessResult
    ) {
      this.isSuccess = businessResult.isSuccess;
      this.message = businessResult.message;
      this.bankAccountsSynced = businessResult.bankAccountsSynced;
      this.creditCardsSynced = businessResult.creditCardsSynced;
      this.connectionsProcessed = businessResult.connectionsProcessed;
      this.transactionsSynced = businessResult.transactionsSynced;
      this.invoicesSynced = businessResult.invoicesSynced;
      this.errors = businessResult.errors;
    }
  }

  /**
   * @description Executa a sincronização síncrona de todas as conexões Pluggy cadastradas.
   */
  @AuraEnabled
  public static SyncExecutionResult performSync() {
    try {
      ALT_CLS_ManualSync businessService = new ALT_CLS_ManualSync();
      return new SyncExecutionResult(businessService.performSync());
    } catch (Exception e) {
      throw new AuraHandledException(
        'Erro ao sincronizar contas: ' + e.getMessage()
      );
    }
  }
}
