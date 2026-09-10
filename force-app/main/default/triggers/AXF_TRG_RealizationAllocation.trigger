trigger AXF_TRG_RealizationAllocation on AXF_OBJ_ReconciliationAllocation__c(
  before insert,
  before update,
  before delete
) {
  ALT_CLS_RealizationGuard.allocations(
    Trigger.isDelete ? Trigger.old : Trigger.new,
    Trigger.oldMap,
    Trigger.isDelete
  );
}
