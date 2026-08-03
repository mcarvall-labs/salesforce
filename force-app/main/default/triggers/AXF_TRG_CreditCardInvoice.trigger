trigger AXF_TRG_CreditCardInvoice on AXF_OBJ_CreditCardInvoice__c (before insert, before update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            AXF_CLS_TH_CreditCardInvoice.handleBeforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            AXF_CLS_TH_CreditCardInvoice.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
