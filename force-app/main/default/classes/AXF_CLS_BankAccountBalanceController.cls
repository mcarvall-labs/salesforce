/**
 * @description Controller Apex do LWC de consulta rápida de saldo em tempo real (US-024).
 * Orquestra a chamada ao AXF_CLS_PluggyBalanceSync_Service e a atualização do registro;
 * a lógica de callout HTTP fica isolada no service, seguindo o mesmo padrão dos demais
 * fluxos de sincronização Pluggy do projeto (Tx, Bill, Account, Investment, Loan).
 */
public with sharing class AXF_CLS_BankAccountBalanceController {

    public class BalanceRefreshResult {
        @AuraEnabled public Boolean isSuccess;
        @AuraEnabled public String message;
        @AuraEnabled public Decimal balance;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public Datetime lastSync;

        public BalanceRefreshResult() {
            this.isSuccess = true;
        }
    }

    /**
     * @description Consulta o saldo atual da conta na Pluggy de forma síncrona (via
     * AXF_CLS_PluggyBalanceSync_Service) e atualiza AXF_BA_CUR_Balance__c / AXF_BA_DAT_LastSync__c
     * no registro correspondente.
     */
    @AuraEnabled
    public static BalanceRefreshResult refreshBalance(Id bankAccountId) {
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