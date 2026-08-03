/**
 * @description Dedicated controller for the aXF_LWC_expenseHomeTable LWC. Thin entry point that
 * delegates to ALT_CLS_CashFlowHome (shared with AXF_CLS_CTRL_RevenueHomeTable at the business
 * layer only, never controller-to-controller), per PROJECT_RULES.md §3.
 */
public with sharing class AXF_CLS_CTRL_ExpenseHomeTable {

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
    public static void settleCashFlow(
        Id cashFlowId,
        Decimal paidValue,
        Date paymentDate,
        Id bankTransactionId,
        Id creditCardTransactionId
    ) {
        try {
            new ALT_CLS_CashFlowSettlement().settleExpense(
                cashFlowId,
                paidValue,
                paymentDate,
                bankTransactionId,
                creditCardTransactionId
            );
        } catch (IllegalArgumentException e) {
            AuraHandledException handled = new AuraHandledException(e.getMessage());
            handled.setMessage(e.getMessage());
            throw handled;
        } catch (Exception e) {
            AuraHandledException handled = new AuraHandledException('Não foi possível liquidar o lançamento.');
            handled.setMessage('Não foi possível liquidar o lançamento.');
            throw handled;
        }
    }
    public class ReconciliationSuggestionDTO {
        @AuraEnabled public Id transactionId;
        @AuraEnabled public String source;
        @AuraEnabled public Date transactionDate;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String description;
        @AuraEnabled public Integer score;
        @AuraEnabled public String confidence;
    }

    @AuraEnabled(cacheable=true)
    public static List<ReconciliationSuggestionDTO> getReconciliationSuggestions(Id cashFlowId) {
        try {
            List<ReconciliationSuggestionDTO> result = new List<ReconciliationSuggestionDTO>();
            for (ALT_CLS_CashFlowSettlement.ReconciliationSuggestion value : new ALT_CLS_CashFlowSettlement().getSuggestions(cashFlowId)) {
                ReconciliationSuggestionDTO dto = new ReconciliationSuggestionDTO();
                dto.transactionId = value.transactionId; dto.source = value.source;
                dto.transactionDate = value.transactionDate; dto.amount = value.amount;
                dto.description = value.description; dto.score = value.score; dto.confidence = value.confidence;
                result.add(dto);
            }
            return result;
        } catch (Exception e) {
            throw handled('Não foi possível sugerir transações para conciliação.');
        }
    }

    @AuraEnabled
    public static void unreconcile(Id cashFlowId) {
        try {
            new ALT_CLS_CashFlowSettlement().unreconcile(cashFlowId);
        } catch (Exception e) {
            throw handled('Não foi possível desfazer a conciliação.');
        }
    }

    private static AuraHandledException handled(String message) {
        AuraHandledException exceptionValue = new AuraHandledException(message);
        exceptionValue.setMessage(message);
        return exceptionValue;
    }}
