/**
 * @description Dedicated controller for the aXF_LWC_realTimeBalance LWC (US-024). Thin entry
 * point that delegates to ALT_CLS_BankAccountBalance for the actual sync/update logic, per
 * PROJECT_RULES.md §3. Renamed from AXF_CLS_BankAccountBalanceController (US-094).
 */
public with sharing class AXF_CLS_CTRL_RealTimeBalance {
  public class BalanceRefreshResult {
    @AuraEnabled
    public Boolean isSuccess;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Decimal balance;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public Datetime lastSync;

    public BalanceRefreshResult(
      ALT_CLS_BankAccountBalance.BalanceRefreshResult businessResult
    ) {
      this.isSuccess = businessResult.isSuccess;
      this.message = businessResult.message;
      this.balance = businessResult.balance;
      this.currencyCode = businessResult.currencyCode;
      this.lastSync = businessResult.lastSync;
    }
  }

  @AuraEnabled
  public static BalanceRefreshResult refreshBalance(Id bankAccountId) {
    if (bankAccountId == null) {
      throw new AuraHandledException('Bank Account ID is required.');
    }
    try {
      ALT_CLS_BankAccountBalance businessService = new ALT_CLS_BankAccountBalance();
      return new BalanceRefreshResult(
        businessService.refreshBalance(bankAccountId)
      );
    } catch (Exception e) {
      throw new AuraHandledException(
        'Erro ao atualizar saldo: ' + e.getMessage()
      );
    }
  }
}
