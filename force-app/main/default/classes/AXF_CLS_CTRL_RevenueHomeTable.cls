/**
 * @description Dedicated controller for the aXF_LWC_revenueHomeTable LWC. Thin entry point that
 * delegates to ALT_CLS_CashFlowHome (shared with AXF_CLS_CTRL_ExpenseHomeTable at the business
 * layer only, never controller-to-controller), per PROJECT_RULES.md §3.
 */
public with sharing class AXF_CLS_CTRL_RevenueHomeTable {

    @AuraEnabled(cacheable=true)
    public static List<AXF_OBJ_CashFlow__c> getMonthlyMovements(String recordTypeDeveloperName, Id categoryId) {
        ALT_CLS_CashFlowHome businessService = new ALT_CLS_CashFlowHome();
        return businessService.getMonthlyMovements(recordTypeDeveloperName, categoryId);
    }

    @AuraEnabled(cacheable=true)
    public static List<AXF_OBJ_BankAccountTransaction__c> searchBankTransactions(String searchTerm) {
        ALT_CLS_CashFlowHome businessService = new ALT_CLS_CashFlowHome();
        return businessService.searchBankTransactions(searchTerm);
    }

    @AuraEnabled(cacheable=true)
    public static List<AXF_OBJ_CreditCardTransaction__c> searchCreditCardTransactions(String searchTerm) {
        ALT_CLS_CashFlowHome businessService = new ALT_CLS_CashFlowHome();
        return businessService.searchCreditCardTransactions(searchTerm);
    }

    @AuraEnabled
    public static void settleCashFlow(Id cashFlowId, String targetStatus, Date paymentDate, Id bankTransactionId, Id creditCardTransactionId) {
        if (cashFlowId == null) {
            throw new AuraHandledException('Cash Flow ID is required.');
        }
        try {
            ALT_CLS_CashFlowHome businessService = new ALT_CLS_CashFlowHome();
            businessService.settleCashFlow(cashFlowId, targetStatus, paymentDate, bankTransactionId, creditCardTransactionId);
        } catch (Exception e) {
            throw new AuraHandledException('Erro ao liquidar lançamento: ' + e.getMessage());
        }
    }
}
