trigger AXF_TRG_BankAccount on AXF_OBJ_BankAccount__c (before insert, before update) {
    AXF_CLS_TH_AccountCardNaming.handleBankAccounts(Trigger.new);
}