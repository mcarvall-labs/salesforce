public with sharing class AXF_CLS_TH_AccountCardNaming {

    public static void handleBankAccounts(List<AXF_OBJ_BankAccount__c> records) {
        Set<Id> accountIds = new Set<Id>();
        Set<Id> institutionIds = new Set<Id>();

        for (AXF_OBJ_BankAccount__c record : records) {
            accountIds.add(record.AXF_BA_LKP_Account__c);
            institutionIds.add(record.AXF_BA_LKP_BankInstitution__c);
        }

        Map<Id, Account> accountsById = queryAccounts(accountIds);
        Map<Id, AXF_OBJ_BankInstitution__c> institutionsById = queryInstitutions(institutionIds);

        for (AXF_OBJ_BankAccount__c record : records) {
            Account holder = accountsById.get(record.AXF_BA_LKP_Account__c);
            AXF_OBJ_BankInstitution__c institution = institutionsById.get(record.AXF_BA_LKP_BankInstitution__c);
            record.Name = AXF_CLS_PluggyAccountSync_Service.buildStandardizedName(
                holder?.Name,
                institution?.Name,
                record.Name,
                System.Label.AXF_LBL_DefaultBankAccountName
            );
        }
    }

    public static void handleCreditCards(List<AXF_OBJ_CreditCard__c> records) {
        Set<Id> accountIds = new Set<Id>();
        Set<Id> institutionIds = new Set<Id>();

        for (AXF_OBJ_CreditCard__c record : records) {
            accountIds.add(record.AXF_CC_LKP_Account__c);
            institutionIds.add(record.AXF_CC_LKP_BankInstitution__c);
        }

        Map<Id, Account> accountsById = queryAccounts(accountIds);
        Map<Id, AXF_OBJ_BankInstitution__c> institutionsById = queryInstitutions(institutionIds);

        for (AXF_OBJ_CreditCard__c record : records) {
            Account holder = accountsById.get(record.AXF_CC_LKP_Account__c);
            AXF_OBJ_BankInstitution__c institution = institutionsById.get(record.AXF_CC_LKP_BankInstitution__c);
            record.Name = AXF_CLS_PluggyAccountSync_Service.buildStandardizedName(
                holder?.Name,
                institution?.Name,
                record.Name,
                System.Label.AXF_LBL_DefaultCreditCardName
            );
        }
    }

    private static Map<Id, Account> queryAccounts(Set<Id> accountIds) {
        accountIds.remove(null);
        if (accountIds.isEmpty()) {
            return new Map<Id, Account>();
        }
        return new Map<Id, Account>([
            SELECT Id, Name
            FROM Account
            WHERE Id IN :accountIds
        ]);
    }

    private static Map<Id, AXF_OBJ_BankInstitution__c> queryInstitutions(Set<Id> institutionIds) {
        institutionIds.remove(null);
        if (institutionIds.isEmpty()) {
            return new Map<Id, AXF_OBJ_BankInstitution__c>();
        }
        return new Map<Id, AXF_OBJ_BankInstitution__c>([
            SELECT Id, Name
            FROM AXF_OBJ_BankInstitution__c
            WHERE Id IN :institutionIds
        ]);
    }
}