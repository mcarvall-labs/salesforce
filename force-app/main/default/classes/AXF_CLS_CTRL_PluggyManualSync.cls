/**
 * @description Dedicated controller for the aXF_LWC_pluggyManualSync LWC (Quick Action manual
 * sync of a single record). Thin entry point that delegates to ALT_CLS_ManualSync for the actual
 * sync orchestration, per PROJECT_RULES.md §3.
 */
public with sharing class AXF_CLS_CTRL_PluggyManualSync {
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
   * @description Dispara a sincronização a partir de um registro específico (LWC Quick Action).
   * startDate/endDate escopam a sincronização a um período específico (dateFrom/dateTo); quando
   * omitidos, ALT_CLS_ManualSync aplica a janela padrão de 3 meses.
   */
  @AuraEnabled
  public static SyncExecutionResult syncRecord(
    Id recordId,
    String sObjectType,
    Date startDate,
    Date endDate
  ) {
    if (recordId == null) {
      throw new AuraHandledException('Record ID is required.');
    }
    if (String.isBlank(sObjectType)) {
      throw new AuraHandledException('SObject type is required.');
    }
    try {
      ALT_CLS_ManualSync businessService = new ALT_CLS_ManualSync();
      return new SyncExecutionResult(
        businessService.syncRecord(recordId, sObjectType, startDate, endDate)
      );
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Erro ao iniciar a sincronização: ' + e.getMessage()
      );
    }
  }
}
