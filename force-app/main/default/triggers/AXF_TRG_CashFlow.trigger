trigger AXF_TRG_CashFlow on AXF_OBJ_CashFlow__c (before insert, before update, after insert, after update, after delete) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            AXF_CLS_TH_CashFlow.handleBeforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            AXF_CLS_TH_CashFlow.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
    } else if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            AXF_CLS_TH_CashFlow.handleAfterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            AXF_CLS_TH_CashFlow.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete) {
            AXF_CLS_TH_CashFlow.handleAfterDelete(Trigger.old);
        }
    }
}
