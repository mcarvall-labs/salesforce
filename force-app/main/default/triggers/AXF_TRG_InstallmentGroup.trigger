trigger AXF_TRG_InstallmentGroup on AXF_OBJ_InstallmentGroup__c (after update) {
    ALT_CLS_SacFinancing.afterGroupRateChange(Trigger.new, Trigger.oldMap);
}
