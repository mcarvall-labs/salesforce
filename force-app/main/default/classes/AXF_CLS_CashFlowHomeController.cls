public with sharing class AXF_CLS_CashFlowHomeController {

    @AuraEnabled(cacheable=true)
    public static List<AXF_OBJ_CashFlow__c> getMonthlyMovements(String recordTypeDeveloperName, Id categoryId) {
        Date today = Date.today();
        Date monthStart = Date.newInstance(today.year(), today.month(), 1);
        Date monthEnd = monthStart.addMonths(1).addDays(-1);

        Map<String, Schema.RecordTypeInfo> rtInfos = AXF_OBJ_CashFlow__c.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
        if (!rtInfos.containsKey(recordTypeDeveloperName)) {
            return new List<AXF_OBJ_CashFlow__c>();
        }
        Id rtId = rtInfos.get(recordTypeDeveloperName).getRecordTypeId();

        String query = 'SELECT Id, Name, AXF_CF_DAT_DueDate__c, AXF_CF_DAT_PaymentDate__c, AXF_CF_PKL_Status__c, ' +
                       '       AXF_CF_CUR_Value__c, AXF_CF_LKP_Category__c, AXF_CF_LKP_Category__r.Name, ' +
                       '       AXF_CF_LKP_BankAccountTransaction__c, AXF_CF_LKP_CreditCardTransaction__c ' +
                       'FROM AXF_OBJ_CashFlow__c ' +
                       'WHERE RecordTypeId = :rtId ' +
                       'AND AXF_CF_DAT_DueDate__c >= :monthStart ' +
                       'AND AXF_CF_DAT_DueDate__c <= :monthEnd ';

        if (categoryId != null) {
            query += 'AND AXF_CF_LKP_Category__c = :categoryId ';
        }

        query += 'ORDER BY AXF_CF_DAT_DueDate__c ASC';

        return Database.query(query);
    }

    @AuraEnabled(cacheable=true)
    public static List<AXF_OBJ_BankAccountTransaction__c> searchBankTransactions(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        return [
            SELECT Id, Name, AXF_BAT_DAT_Date__c, AXF_BAT_TXT_Description__c, AXF_BAT_CUR_Amount__c
            FROM AXF_OBJ_BankAccountTransaction__c
            WHERE AXF_BAT_TXT_Description__c LIKE :term
            ORDER BY AXF_BAT_DAT_Date__c DESC
            LIMIT 10
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<AXF_OBJ_CreditCardTransaction__c> searchCreditCardTransactions(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        return [
            SELECT Id, Name, AXF_CCT_DAT_Date__c, AXF_CCT_TXT_Description__c, AXF_CCT_CUR_Amount__c
            FROM AXF_OBJ_CreditCardTransaction__c
            WHERE AXF_CCT_TXT_Description__c LIKE :term
            ORDER BY AXF_CCT_DAT_Date__c DESC
            LIMIT 10
        ];
    }

    @AuraEnabled
    public static void settleCashFlow(Id cashFlowId, String targetStatus, Date paymentDate, Id bankTransactionId, Id creditCardTransactionId) {
        AXF_OBJ_CashFlow__c cf = new AXF_OBJ_CashFlow__c(Id = cashFlowId);
        cf.AXF_CF_PKL_Status__c = targetStatus;
        cf.AXF_CF_DAT_PaymentDate__c = paymentDate;
        if (bankTransactionId != null) {
            cf.AXF_CF_LKP_BankAccountTransaction__c = bankTransactionId;
        }
        if (creditCardTransactionId != null) {
            cf.AXF_CF_LKP_CreditCardTransaction__c = creditCardTransactionId;
        }
        update cf;
    }
}