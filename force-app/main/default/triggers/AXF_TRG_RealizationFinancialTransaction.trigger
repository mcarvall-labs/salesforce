trigger AXF_TRG_RealizationFinancialTransaction on AXF_OBJ_FinancialTransaction__c(
  before insert,
  before update,
  before delete
) {
  ALT_CLS_RealizationGuard.originals(
    Trigger.isDelete ? Trigger.old : Trigger.new,
    Trigger.oldMap,
    Trigger.isDelete
  );
}
