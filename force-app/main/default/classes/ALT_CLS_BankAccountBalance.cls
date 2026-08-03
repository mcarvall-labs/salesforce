/**
 * @description Business service layer for real-time Bank Account balance refresh via Pluggy.
 * Orchestrates the call to AXF_CLS_PluggyBalanceSync_Service and the record update; callout HTTP
 * logic stays isolated in the service, following the same pattern as the other Pluggy sync flows
 * (Tx, Bill, Account, Investment, Loan). Consumed by AXF_CLS_CTRL_RealTimeBalance. Contains no
 * @AuraEnabled members and no LWC-specific concepts, per PROJECT_RULES.md §3.
 */
public inherited sharing class ALT_CLS_BankAccountBalance {

    public class BalanceRefreshResult {
        public Boolean isSuccess;
        public String message;
        public Decimal balance;
        public String currencyCode;
        public Datetime lastSync;

        public BalanceRefreshResult() {
            this.isSuccess = true;
        }
    }

    /**
     * @description Consulta o saldo atual da conta na Pluggy de forma síncrona (via
     * AXF_CLS_PluggyBalanceSync_Service) e atualiza AXF_BA_CUR_Balance__c / AXF_BA_DAT_LastSync__c
     * no registro correspondente.
     */
    public BalanceRefreshResult refreshBalance(Id bankAccountId) {
        BalanceRefreshResult result = new BalanceRefreshResult();

        AXF_OBJ_BankAccount__c account = [
            SELECT AXF_BA_EXI_PluggyAccountId__c
            FROM AXF_OBJ_BankAccount__c
            WHERE Id = :bankAccountId
            LIMIT 1
        ];

        if (String.isBlank(account.AXF_BA_EXI_PluggyAccountId__c)) {
            result.isSuccess = false;
            result.message = 'Esta Conta Bancária não possui um ID Pluggy válido associado.';
            return result;
        }

        try {
            String apiKey = AXF_CLS_PluggyAuthService.getValidApiKey();
            AXF_CLS_PluggyBalanceSync_Service.BalanceResult balanceResult = AXF_CLS_PluggyBalanceSync_Service.fetchBalance(
                account.AXF_BA_EXI_PluggyAccountId__c,
                apiKey
            );

            result.balance = balanceResult.balance;
            result.currencyCode = balanceResult.currencyCode;
            result.lastSync = balanceResult.lastSync != null ? balanceResult.lastSync : Datetime.now();

            update new AXF_OBJ_BankAccount__c(
                Id = bankAccountId,
                AXF_BA_CUR_Balance__c = result.balance,
                AXF_BA_DAT_LastSync__c = result.lastSync
            );

            result.message = 'Saldo atualizado com sucesso.';
        } catch (Exception e) {
            result.isSuccess = false;
            result.message = 'Erro ao atualizar saldo: ' + e.getMessage();
        }

        return result;
    }
}
