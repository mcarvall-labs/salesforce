trigger AXF_TRG_CashFlow on AXF_OBJ_CashFlow__c (before insert, before update, before delete, after insert, after update, after delete) {
    if (Trigger.isBefore) {
        if (Trigger.isDelete) { AXF_CLS_TH_Reconciliation.preventCashFlowDelete(Trigger.old); return; }
        AXF_CLS_TH_Reconciliation.validateCashFlows(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
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
