trigger AXF_TRG_InstallmentGroup on AXF_OBJ_InstallmentGroup__c(after update) {
  if (Trigger.isAfter && Trigger.isUpdate) {
    AXF_CLS_IGTriggerHandler.handleAfterUpdate(
      Trigger.new,
      (Map<Id, AXF_OBJ_InstallmentGroup__c>) Trigger.oldMap
    );
  }
}
