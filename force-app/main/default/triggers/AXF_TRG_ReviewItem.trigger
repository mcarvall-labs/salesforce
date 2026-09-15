/** @description Protects review evidence, typed references, terminal decisions and retention. */
trigger AXF_TRG_ReviewItem on AXF_OBJ_ReviewItem__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_ReviewQueueTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_ReviewQueueTriggerHandler.handleBeforeUpdate(
      Trigger.new,
      Trigger.oldMap
    );
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_ReviewQueueTriggerHandler.handleBeforeDelete(Trigger.old);
  }
}
