trigger AXF_TRG_CreditCardTransaction on AXF_OBJ_CreditCardTransaction__c (before insert, before update, before delete) {
    if (Trigger.isDelete) AXF_CLS_TH_Reconciliation.preventCardDelete(Trigger.old);
    else AXF_CLS_TH_Reconciliation.validateCards(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
}
