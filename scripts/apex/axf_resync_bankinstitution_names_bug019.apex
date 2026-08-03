// Data fix - BUG-019 / GitHub Issue #227
// The picklist value AXF_OBJ_BankInstitution__c.AXF_BI_PKL_BankName__c was renamed
// from "Caixa Econômica Federal" to "CEF" directly in Setup, which does not touch
// any BankInstitution record, so AXF_CLS_TH_BankInstitution (which only recalculates
// Name on save) never fired and Name stayed stale ("Caixa Econômica Federal (104)").
//
// AXF_OBJ_BankAccount__c / AXF_OBJ_CreditCard__c had the same staleness one level
// down: AXF_CLS_TH_AccountCardNaming already recalculates their Name on every save
// by calling AXF_CLS_PluggyAccountSync_Service.buildStandardizedName(...) with the
// live BankInstitution.Name, but nothing re-saved them after the rename either.
//
// This script does NOT duplicate the naming logic. It simply performs a
// trigger-safe `update` (no field values changed) on the affected records so the
// existing trigger handlers (AXF_CLS_TH_BankInstitution, AXF_CLS_TH_AccountCardNaming)
// recompute Name from current data, in the correct order: BankInstitution first,
// then the downstream BankAccount/CreditCard records that read its Name.
// Idempotent: re-running after Names are already correct is a no-op update.

List<AXF_OBJ_BankInstitution__c> institutionsToResync = [
    SELECT Id, Name, AXF_BI_PKL_BankName__c, AXF_BI_EXI_Bank_Number__c
    FROM AXF_OBJ_BankInstitution__c
    WHERE AXF_BI_EXI_Bank_Number__c = '104'
];

if (!institutionsToResync.isEmpty()) {
    update institutionsToResync;
}

Set<Id> institutionIds = new Set<Id>();
for (AXF_OBJ_BankInstitution__c inst : institutionsToResync) {
    institutionIds.add(inst.Id);
}

List<AXF_OBJ_BankAccount__c> bankAccountsToResync = institutionIds.isEmpty()
    ? new List<AXF_OBJ_BankAccount__c>()
    : [
        SELECT Id, Name
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_LKP_BankInstitution__c IN :institutionIds
    ];

if (!bankAccountsToResync.isEmpty()) {
    update bankAccountsToResync;
}

List<AXF_OBJ_CreditCard__c> creditCardsToResync = institutionIds.isEmpty()
    ? new List<AXF_OBJ_CreditCard__c>()
    : [
        SELECT Id, Name
        FROM AXF_OBJ_CreditCard__c
        WHERE AXF_CC_LKP_BankInstitution__c IN :institutionIds
    ];

if (!creditCardsToResync.isEmpty()) {
    update creditCardsToResync;
}

System.debug(LoggingLevel.INFO, 'BUG-019 bank institutions resynced: ' + institutionsToResync.size());
System.debug(LoggingLevel.INFO, 'BUG-019 bank accounts resynced: ' + bankAccountsToResync.size());
System.debug(LoggingLevel.INFO, 'BUG-019 credit cards resynced: ' + creditCardsToResync.size());
