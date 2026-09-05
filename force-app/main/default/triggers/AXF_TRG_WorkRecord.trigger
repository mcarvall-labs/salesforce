/**
 * @description Trigger para AXF_OBJ_WorkRecord__c (AXF-56).
 */
trigger AXF_TRG_WorkRecord on AXF_OBJ_WorkRecord__c (before insert, before update, before delete) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_WorkRecordTriggerHandler.handleBeforeInsert(Trigger.new);
  } else if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_WorkRecordTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  } else if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_WorkRecordTriggerHandler.handleBeforeDelete(Trigger.old);
  }
}
