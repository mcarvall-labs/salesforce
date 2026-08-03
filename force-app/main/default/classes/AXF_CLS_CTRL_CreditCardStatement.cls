/**
 * @description Dedicated controller for the aXF_LWC_creditCardStatement LWC. Thin entry point
 * that delegates to ALT_CLS_CreditCardStatement for the actual query/calculation logic, per
 * PROJECT_RULES.md §3. Renamed from AXF_CLS_CreditCardStatementController (US-094).
 */
public with sharing class AXF_CLS_CTRL_CreditCardStatement {

    public class StatementResult {
        @AuraEnabled public List<TransactionRow> transactions;
        @AuraEnabled public Decimal totalCredits;
        @AuraEnabled public Decimal totalDebits;
        @AuraEnabled public Decimal netBalance;

        public StatementResult() {
            this.transactions = new List<TransactionRow>();
            this.totalCredits = 0;
            this.totalDebits = 0;
            this.netBalance = 0;
        }
    }

    public class TransactionRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Datetime transactionDate;
        @AuraEnabled public String description;
        @AuraEnabled public String categoryName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Boolean isCredit;

        public TransactionRow(ALT_CLS_CreditCardStatement.TransactionRow row) {
            this.id = row.id;
            this.transactionDate = row.transactionDate;
            this.description = row.description;
            this.categoryName = row.categoryName;
            this.amount = row.amount;
            this.isCredit = row.isCredit;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<AXF_OBJ_CreditCardInvoice__c> getInvoices(Id creditCardId) {
        ALT_CLS_CreditCardStatement businessService = new ALT_CLS_CreditCardStatement();
        return businessService.getInvoices(creditCardId);
    }

    @AuraEnabled(cacheable=true)
    public static StatementResult getStatement(
        Id invoiceId,
        String description,
        Decimal valueMin,
        Decimal valueMax
    ) {
        ALT_CLS_CreditCardStatement businessService = new ALT_CLS_CreditCardStatement();
        ALT_CLS_CreditCardStatement.StatementResult businessResult = businessService.getStatement(
            invoiceId, description, valueMin, valueMax
        );

        StatementResult result = new StatementResult();
        result.totalCredits = businessResult.totalCredits;
        result.totalDebits = businessResult.totalDebits;
        result.netBalance = businessResult.netBalance;
        for (ALT_CLS_CreditCardStatement.TransactionRow row : businessResult.transactions) {
            result.transactions.add(new TransactionRow(row));
        }
        return result;
    }
}
