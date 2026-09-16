trigger AXF_TRG_ArchiveRun on AXF_OBJ_ArchiveRun__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isInsert) {
    AXF_CLS_ArchiveRunTriggerHandler.handleBeforeInsert(Trigger.new);
  } else if (Trigger.isUpdate) {
    AXF_CLS_ArchiveRunTriggerHandler.handleBeforeUpdate(
      Trigger.new,
      Trigger.oldMap
    );
  } else if (Trigger.isDelete) {
    AXF_CLS_ArchiveRunTriggerHandler.handleBeforeDelete(
      Trigger.old,
      Trigger.oldMap
    );
  }
}
