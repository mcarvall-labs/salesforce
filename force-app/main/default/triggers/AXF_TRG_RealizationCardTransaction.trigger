trigger AXF_TRG_RealizationCardTransaction on AXF_OBJ_CreditCardTransaction__c(
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
