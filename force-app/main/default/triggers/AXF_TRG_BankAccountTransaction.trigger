trigger AXF_TRG_BankAccountTransaction on AXF_OBJ_BankAccountTransaction__c (before insert, before update, before delete) {
    if (Trigger.isDelete) AXF_CLS_TH_Reconciliation.preventBankDelete(Trigger.old);
    else AXF_CLS_TH_Reconciliation.validateBanks(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
}
