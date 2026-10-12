trigger AXF_TRG_Category on AXF_OBJ_Category__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isDelete) {
    AXF_CLS_CategoryHandler.handleBeforeDelete(Trigger.old);
  } else {
    AXF_CLS_CategoryHandler.handleBeforeSave(Trigger.new);
  }
}
